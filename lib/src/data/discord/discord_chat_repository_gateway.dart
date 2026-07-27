part of 'discord_chat_repository.dart';

/// The gateway side of the bot transport.
///
/// Every dispatch the socket hands back is routed and translated here. That is
/// a job of its own — read the payload, write the cache, announce the result —
/// so it sits beside the repository rather than inside it, leaving the class
/// itself about the calls a caller makes.
extension _DiscordChatRepositoryGateway on DiscordChatRepository {
  void _onGatewayEvent(DiscordGatewayEvent event) {
    switch (event) {
      case DiscordGatewayStatusEvent():
        _events.addStatus(switch (event.status) {
          DiscordGatewayStatus.offline => RepositoryConnectionStatus.offline,
          DiscordGatewayStatus.connecting =>
            RepositoryConnectionStatus.connecting,
          DiscordGatewayStatus.connected =>
            RepositoryConnectionStatus.connected,
          DiscordGatewayStatus.reconnecting =>
            RepositoryConnectionStatus.reconnecting,
        });
      case DiscordGatewayDispatch():
        switch (event.name) {
          case 'MESSAGE_CREATE' || 'MESSAGE_UPDATE':
            unawaited(_handleMessageDispatch(event));
          case 'MESSAGE_DELETE':
            unawaited(_handleMessageDelete(event.data));
          case 'MESSAGE_REACTION_ADD' || 'MESSAGE_REACTION_REMOVE':
            unawaited(_handleReaction(event));
          case 'MESSAGE_POLL_VOTE_ADD' || 'MESSAGE_POLL_VOTE_REMOVE':
            unawaited(_handlePollVote(event));
          case 'CHANNEL_CREATE' ||
              'CHANNEL_UPDATE' ||
              'THREAD_CREATE' ||
              'THREAD_UPDATE':
            unawaited(_handleChannelUpsert(event.data));
          case 'CHANNEL_DELETE' || 'THREAD_DELETE':
            unawaited(_handleChannelDelete(event.data));
          case 'GUILD_MEMBER_ADD' || 'GUILD_MEMBER_UPDATE':
            unawaited(_handleMemberUpsert(event.data));
          case 'GUILD_MEMBER_REMOVE':
            _handleMemberRemove(event.data);
          case 'PRESENCE_UPDATE':
            _handlePresence(event.data);
          case 'TYPING_START':
            _handleTyping(event.data);
          case 'CHANNEL_PINS_UPDATE':
            _handlePinsChanged(event.data);
          case 'GUILD_CREATE':
            _handleGuildSnapshot(event.data);
          case 'GUILD_EMOJIS_UPDATE':
            unawaited(_handleGuildEmojis(event.data));
          case 'GUILD_STICKERS_UPDATE':
            unawaited(_handleGuildStickers(event.data));
          case 'GUILD_SCHEDULED_EVENT_CREATE' ||
              'GUILD_SCHEDULED_EVENT_UPDATE' ||
              'GUILD_SCHEDULED_EVENT_DELETE' ||
              'GUILD_SCHEDULED_EVENT_USER_ADD' ||
              'GUILD_SCHEDULED_EVENT_USER_REMOVE':
            unawaited(_handleGuildScheduledEvent(event));
        }
    }
  }

  Future<void> _handleMessageDelete(Map<String, Object?> data) async {
    final messageId = data['id'] as String?;
    final channelId = data['channel_id'] as String?;
    if (messageId == null || channelId == null) return;
    await _cache.deleteMessage(messageId);
    if (!_events.isClosed) {
      _events.add(
        MessageDeletedEvent(messageId: messageId, channelId: channelId),
      );
    }
  }

  Future<void> _handleReaction(DiscordGatewayDispatch event) async {
    final update = await _reactionHandler.apply(event);
    if (update != null && !_events.isClosed) _events.add(update);
  }

  Future<void> _handleChannelUpsert(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId == null) {
      final currentUserId = _currentMemberId;
      if (currentUserId == null) return;
      final conversation = await _directMessages.acceptChannel(
        data,
        currentUserId,
      );
      if (conversation != null) _emitDirectConversation(conversation);
      return;
    }
    final update = await _channelHandler.upsert(data, guildId);
    if (update != null && !_events.isClosed) _events.add(update);
  }

  Future<void> _handleChannelDelete(Map<String, Object?> data) async {
    final update = await _channelHandler.delete(data);
    if (update != null && !_events.isClosed) _events.add(update);
  }

  Future<void> _handleMemberUpsert(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId == null || data['user'] is! Map) return;
    final member = _mapper.guildMember(
      data,
      guildId,
      _rolesByGuild[guildId] ?? const [],
    );
    await _cache.writeMember(member);
    if (!_events.isClosed) _events.add(MemberUpsertedEvent(member));
  }

  void _handleMemberRemove(Map<String, Object?> data) {
    final guildId = data['guild_id'] as String?;
    final user = data['user'];
    final memberId = user is Map ? user['id'] as String? : null;
    if (guildId == null || memberId == null || _events.isClosed) return;
    _events.add(MemberRemovedEvent(memberId: memberId, spaceId: guildId));
  }

  void _handlePresence(Map<String, Object?> data) {
    if (_events.isClosed) return;
    final record = DiscordPresenceMapper.record(data);
    if (record == null) return;
    _events.add(
      PresenceChangedEvent(memberId: record.userId, presence: record.presence),
    );
  }

  void _handleTyping(Map<String, Object?> data) {
    final channelId = data['channel_id'] as String?;
    final memberId = data['user_id'] as String?;
    if (channelId == null || memberId == null || _events.isClosed) return;
    _events.add(TypingStartedEvent(channelId: channelId, memberId: memberId));
  }

  void _handlePinsChanged(Map<String, Object?> data) {
    final channelId = data['channel_id'] as String?;
    if (channelId != null && !_events.isClosed) {
      _events.add(PinsChangedEvent(channelId));
    }
  }

  void _handleGuildSnapshot(Map<String, Object?> data) {
    final guildId = data['id'] as String?;
    if (guildId == null) return;
    if (data['emojis'] is List) unawaited(_handleGuildEmojis(data));
    final roles = data['roles'];
    if (roles is List) {
      _rolesByGuild[guildId] = roles
          .whereType<Map>()
          .map((role) => role.cast<String, Object?>())
          .toList(growable: false);
    }
    final members = data['members'];
    if (members is List && !_events.isClosed) {
      for (final raw in members.whereType<Map>()) {
        final payload = raw.cast<String, Object?>();
        if (payload['user'] is! Map) continue;
        _events.add(
          MemberUpsertedEvent(
            _mapper.guildMember(
              payload,
              guildId,
              _rolesByGuild[guildId] ?? const [],
            ),
          ),
        );
      }
    }
    final presences = data['presences'];
    if (presences is List) {
      for (final raw in presences.whereType<Map>()) {
        _handlePresence(raw.cast<String, Object?>());
      }
    }
  }
}
