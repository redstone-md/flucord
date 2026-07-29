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
        }
    }
  }

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
