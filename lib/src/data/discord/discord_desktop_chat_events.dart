part of 'discord_desktop_chat_repository.dart';

/// The gateway side of the desktop transport.
///
/// Every dispatch the socket hands back lands here and turns into a
/// repository event, and that translation is a self-contained job: it reads
/// the payload, writes the cache and announces the result. Keeping it beside
/// the transport rather than inside it leaves the class itself about the
/// calls a caller makes.
extension _DiscordDesktopChatEvents on DiscordDesktopChatRepository {
  void _acceptGatewayEvent(DiscordGatewayEvent event) {
    switch (event) {
      case DiscordGatewayStatusEvent():
        _emitStatus(switch (event.status) {
          DiscordGatewayStatus.offline => RepositoryConnectionStatus.offline,
          DiscordGatewayStatus.connecting =>
            RepositoryConnectionStatus.connecting,
          DiscordGatewayStatus.connected =>
            RepositoryConnectionStatus.connected,
          DiscordGatewayStatus.reconnecting =>
            RepositoryConnectionStatus.reconnecting,
        });
      case DiscordGatewayDispatch():
        // The settings store reads READY for the blob it is handed at login
        // and USER_SETTINGS_PROTO_UPDATE for every later revision, so it also
        // sees every dispatch.
        _userSettings.acceptGatewayDispatch(event.name, event.data);
        // Notes ride the same account stream: READY carries the whole map
        // and USER_NOTE_UPDATE revises one entry.
        _userNotes.acceptGatewayDispatch(event.name, event.data);
        // Favourites are a second settings type on the same dispatch, and
        // one starred on another device arrives here unasked for.
        _favorites.acceptGatewayDispatch(event.name, event.data);
        // The member-list handler needs READY and GUILD_CREATE for the channel
        // shape a list id is derived from, so it sees every dispatch rather
        // than only the roster event.
        final members = _memberLists.accept(event.name, event.data);
        if (members.isNotEmpty) _events.add(MembersUpsertedEvent(members));
        // A chunk answers opcode 8. The presence service already reads the
        // presences out of it; the members themselves are what makes somebody
        // mentionable who was not in READY at all.
        if (event.name == 'GUILD_MEMBERS_CHUNK') {
          final chunked = _mapper.membersFromChunk(event.data);
          if (chunked.isNotEmpty) _events.add(MembersUpsertedEvent(chunked));
        }
        _acceptPresence(event);
        // Read state hangs off READY and five ack dispatches, so it too sees
        // the whole stream rather than a hand-picked slice of it.
        _readState.acceptGatewayDispatch(event.name, event.data);
        // Thread membership answers to four dispatches and has to see them all:
        // a join made on another device arrives as THREAD_MEMBER_UPDATE with no
        // request from here.
        _threadMembership.accept(event.name, event.data);
        // A stage running before this client connected is only ever announced
        // in the bootstrap burst, so the service sees every dispatch too.
        _stages.accept(event.name, event.data);
        // Soundboard sounds change without being asked for, and an effect
        // somebody else sent arrives on the same stream.
        _soundboard.accept(event.name, event.data);
        // A modal is opened by the application, not asked for here.
        _messageComponents.accept(event.name, event.data);
        _goLive.accept(event.name, event.data);
        _summaries.accept(event.name, event.data);
        // READY carries the whole friend graph, and three dispatches keep it
        // current. There is no route to re-read it, so missing one means
        // showing a friend list that is quietly wrong.
        _relationships.accept(event.name, event.data);
        if (event.name == 'MESSAGE_CREATE' || event.name == 'MESSAGE_UPDATE') {
          unawaited(_acceptMessage(event));
        } else if (event.name == 'MESSAGE_DELETE') {
          unawaited(_acceptDelete(event.data));
        } else if (event.name == 'TYPING_START') {
          _acceptTyping(event.data);
        } else if (event.name == 'PASSIVE_UPDATE_V2') {
          _acceptPassiveUpdate(event.data);
        } else if (event.name == 'READY' ||
            event.name == 'READY_SUPPLEMENTAL') {
          unawaited(_rehydrateWorkspace());
        }
    }
  }

  /// Applies a post-load READY to the workspace in place.
  ///
  /// A reconnect that could not resume identifies again, and the READY that
  /// comes back is the authoritative guild and channel list. Rebuilding the
  /// workspace around it wholesale would drop every held history and unread
  /// boundary, so the change is computed against the cached shell and
  /// announced as ordinary upserts and deletions instead. The same READY also
  /// re-arms `READY_SUPPLEMENTAL`, whose lazy private channels land through
  /// the second pass; a pass that changes nothing announces nothing.
  Future<void> _rehydrateWorkspace() async {
    try {
      await _rehydrateWorkspaceNow();
    } catch (error, stackTrace) {
      // A hydration that cannot be applied must not take the session down:
      // the workspace keeps what it had until the next full load.
      AppLog.warning(
        'discord.desktop',
        'Discord desktop rehydration failed: ${_diagnosticFor(error)} '
            '($stackTrace)',
        error: error,
      );
    }
  }

  Future<void> _rehydrateWorkspaceNow() async {
    if (!_workspaceShown || _events.isClosed) return;
    final snapshot = _gateway.workspaceSnapshot;
    if (snapshot == null) return;
    final cached = await _cache.readWorkspaceShell();
    if (cached == null) return;
    final fresh = _mapper
        .workspace(
          currentUser: snapshot.currentUser,
          guilds: snapshot.guilds,
          channelsByGuild: snapshot.channelsByGuild,
          rolesByGuild: snapshot.rolesByGuild,
          membersByGuild: snapshot.membersByGuild,
          directChannels: snapshot.directChannels,
          includeDirectMessagesSpace: true,
          currentUserRole: 'Discord user',
        )
        // The activity is restored so the comparison below sees only what
        // Discord changed, and an unchanged channel announces nothing.
        .restoreChannelActivityFrom(cached);
    if (_events.isClosed) return;

    for (final space in cached.spaces) {
      if (fresh.spaceOrNull(space.id) == null) {
        // The cached copy goes at the next wholesale load; the rail goes now.
        _events.add(SpaceRemovedEvent(space.id));
      }
    }
    for (final channel in cached.channels) {
      if (fresh.channelOrNull(channel.id) == null) {
        _events.add(ChannelDeletedEvent(channel.id));
        await _cache.deleteChannel(channel.id);
      }
    }
    for (final category in cached.categories) {
      if (fresh.categoryOrNull(category.id) == null) {
        _events.add(CategoryDeletedEvent(category.id));
        await _cache.deleteCategory(category.id);
      }
    }
    for (final space in fresh.spaces) {
      final existing = cached.spaceOrNull(space.id);
      if (existing == null || _spaceChanged(space, existing)) {
        _events.add(SpaceUpsertedEvent(space));
        await _cache.writeSpace(space);
      }
    }
    for (final category in fresh.categories) {
      final existing = cached.categoryOrNull(category.id);
      if (existing == null || _categoryChanged(category, existing)) {
        _events.add(CategoryUpsertedEvent(category));
        await _cache.writeCategory(category);
      }
    }
    for (final channel in fresh.channels) {
      final existing = cached.channelOrNull(channel.id);
      if (existing == null || _channelChanged(channel, existing)) {
        _events.add(ChannelUpsertedEvent(channel));
        await _cache.writeChannel(channel);
      }
      // A direct message the account has never seen here needs its recipient
      // row. A recipient who only changed their name keeps the cached row
      // until the next full load: the shell carries no members to diff
      // against, and decoding the whole cache per dispatch would cost more
      // than the staleness does.
      final recipientId = channel.recipientId;
      if (recipientId != null && existing == null) {
        final recipient = fresh.memberOrNull(recipientId);
        if (recipient != null) _events.add(MemberUpsertedEvent(recipient));
      }
    }
    // R09 computes `private_channels_version` over the private channels, and
    // the rehydrated list is what the account holds now.
    _adoptPrivateChannels(fresh);
  }

  static bool _spaceChanged(CommunitySpace next, CommunitySpace cached) =>
      next.name != cached.name ||
      next.iconUrl != cached.iconUrl ||
      next.ownerId != cached.ownerId ||
      next.requiresMultiFactorAuth != cached.requiresMultiFactorAuth;

  static bool _categoryChanged(ChannelCategory next, ChannelCategory cached) =>
      next.name != cached.name || next.position != cached.position;

  static bool _channelChanged(
    ConversationChannel next,
    ConversationChannel cached,
  ) => _channelSignature(next) != _channelSignature(cached);

  /// Channels carry no value equality, so the fields a reconnect READY can
  /// change are flattened into one comparable string. The permission
  /// overwrites ride along because they decide what the account can see.
  static String _channelSignature(ConversationChannel channel) => [
    channel.name,
    channel.topic,
    channel.kind.index,
    channel.position,
    ?channel.parentId,
    channel.isArchived,
    channel.isLocked,
    ?channel.lastMessageId,
    ?channel.recipientId,
    _overwriteSignature(channel.permissionOverwrites),
  ].join('|');

  static String _overwriteSignature(
    Map<String, DiscordPermissionOverwrite> overwrites,
  ) => overwrites.entries
      .map(
        (entry) =>
            '${entry.key}:${entry.value.allow}/${entry.value.deny}/'
            '${entry.value.kind.index}',
      )
      .join(',');

  // Comparing signatures rather than fields is what lets one changed field and
  // ten of them read the same way.

  /// Feeds one dispatch to the presence plane and publishes what it changed.
  ///
  /// Every dispatch is offered, not only `PRESENCE_UPDATE`: R07 lists seven
  /// more events that carry presence — READY's sessions, the supplemental
  /// merge, guild snapshots, member chunks and the lazy member list among them
  /// — and on this transport those bulk paths deliver almost everything, with
  /// the incremental event only covering what changes afterwards.
  void _acceptPresence(DiscordGatewayDispatch event) {
    final changed = _presence.accept(event.name, event.data);
    if (event.name == 'READY') {
      _presence.sessionEstablished();
      _emitSelfPresence();
    }
    if (changed.isNotEmpty && !_events.isClosed) {
      _events.add(PresencesChangedEvent(changed));
    }
  }

  /// R04: `PASSIVE_UPDATE_V2` refreshes the last-message and last-pin pointers
  /// of a guild the client holds no live subscription for. Only the pointers
  /// travel — there is no message to store — so this is the one place unread
  /// can change without a `MESSAGE_CREATE`.
  void _acceptPassiveUpdate(Map<String, Object?> data) {
    final channels = data['channels'];
    if (channels is! List) return;
    for (final entry in channels.whereType<Map>()) {
      final channelId = entry['id'];
      final messageId = entry['last_message_id'];
      if (channelId is! String || messageId is! String) continue;
      _events.add(
        ChannelLastMessageEvent(channelId: channelId, messageId: messageId),
      );
    }
  }

  Future<void> _acceptMessage(DiscordGatewayDispatch event) async {
    final messageId = event.data['id'];
    if (messageId is! String) return;
    final fallback = event.name == 'MESSAGE_UPDATE'
        ? await _cache.readMessage(messageId)
        : null;
    if (event.name == 'MESSAGE_UPDATE' && fallback == null) return;
    final message = await _storeMessage(event.data, fallback: fallback);
    final rawAuthor = event.data['author'];
    final member = rawAuthor is Map
        ? _mapper.member(
            rawAuthor.cast<String, Object?>(),
            spaceIds: {
              if (event.data['guild_id'] case final String guildId) guildId,
              if (event.data['guild_id'] == null)
                DiscordMapper.directMessagesSpaceId,
            },
          )
        : null;
    if (member != null) await _cache.writeMember(member);
    _events.add(
      MessageUpsertedEvent(
        message: message,
        member: member,
        isNew: event.name == 'MESSAGE_CREATE',
        mentionsCurrentMember: message.mentionsCurrentMember,
      ),
    );
  }

  Future<ChatMessage> _storeMessage(
    Map<String, Object?> payload, {
    ChatMessage? fallback,
  }) async {
    final message = _mapper.message(
      payload,
      fallback: fallback,
      currentMemberId: _currentMemberId,
    );
    await _cache.writeMessage(message);
    return message;
  }

  Future<void> _acceptDelete(Map<String, Object?> data) async {
    final messageId = data['id'];
    final channelId = data['channel_id'];
    if (messageId is! String || channelId is! String) return;
    await _cache.deleteMessage(messageId);
    _events.add(
      MessageDeletedEvent(messageId: messageId, channelId: channelId),
    );
  }

  void _acceptTyping(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    final memberId = data['user_id'];
    if (channelId is String && memberId is String) {
      _events.add(TypingStartedEvent(channelId: channelId, memberId: memberId));
    }
  }

  void _emitStatus(RepositoryConnectionStatus status) {
    if (!_events.isClosed) _events.add(RepositoryStatusChangedEvent(status));
  }
}
