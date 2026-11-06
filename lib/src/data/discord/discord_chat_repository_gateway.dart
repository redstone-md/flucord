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
        _sharedDispatches.route(event);
        switch (event.name) {
          case 'MESSAGE_CREATE':
            _sharedDispatches.acceptNewMessage(
              event.data,
              read: (payload) =>
                  _mapper.message(payload, currentMemberId: _currentMemberId),
            );
          case 'PRESENCE_UPDATE':
            _handlePresence(event.data);
          case 'TYPING_START':
            _handleTyping(event.data);
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
          case 'GUILD_SCHEDULED_EVENT_EXCEPTION_CREATE' ||
              'GUILD_SCHEDULED_EVENT_EXCEPTION_UPDATE' ||
              'GUILD_SCHEDULED_EVENT_EXCEPTION_DELETE' ||
              'GUILD_SCHEDULED_EVENT_EXCEPTIONS_DELETE':
            unawaited(_handleGuildScheduledEventException(event));
        }
    }
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

  void _handleGuildSnapshot(Map<String, Object?> data) {
    final guildId = data['id'] as String?;
    if (guildId == null) return;
    if (data['emojis'] is List) unawaited(_handleGuildEmojis(data));
    final members = data['members'];
    if (members is List && !_events.isClosed) {
      for (final raw in members.whereType<Map>()) {
        final payload = raw.cast<String, Object?>();
        if (payload['user'] is! Map) continue;
        _events.add(MemberUpsertedEvent(_mapper.guildMember(payload, guildId)));
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
