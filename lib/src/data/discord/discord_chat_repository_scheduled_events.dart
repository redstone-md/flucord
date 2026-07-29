part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryScheduledEvents
    implements ScheduledEventRepository {
  DiscordApiClient get _api;
  DiscordMapper get _mapper;
  ChatCache get _cache;
  StreamController<ChatRepositoryEvent> get _events;

  @override
  Future<List<GuildScheduledEvent>> loadScheduledEvents(String spaceId) async {
    try {
      final payloads = await _api.getGuildScheduledEvents(spaceId);
      final events =
          payloads
              .map(
                (payload) => _mapper.guildScheduledEvent(
                  payload,
                  fallbackSpaceId: spaceId,
                ),
              )
              .whereType<GuildScheduledEvent>()
              .toList(growable: false)
            ..sort(GuildScheduledEvent.compareForDisplay);
      await _cache.replaceGuildScheduledEvents(spaceId, events);
      return events;
    } catch (_) {
      final cached = await _cache.readGuildScheduledEvents(spaceId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  @override
  Future<bool> setEventInterest({
    required String spaceId,
    required String eventId,
    required bool interested,
    String? exceptionId,
  }) async {
    try {
      await _api.setGuildScheduledEventInterest(
        guildId: spaceId,
        eventId: eventId,
        interested: interested,
        exceptionId: exceptionId,
      );
    } on DiscordApiException catch (error) {
      // An event that has ended, or one this account cannot see, is refused.
      // That is an answer about the event rather than a fault here.
      if (error.statusCode == 400 || error.statusCode == 403) return false;
      rethrow;
    }
    // Discord echoes the change back as GUILD_SCHEDULED_EVENT_USER_ADD, which
    // moves the count. Nothing is patched locally: two places counting the
    // same thing is how a count ends up wrong by one forever.
    return true;
  }

  Future<void> _handleGuildScheduledEvent(DiscordGatewayDispatch event) async {
    final data = event.data;
    final spaceId = data['guild_id'] as String?;
    final eventId = (data['guild_scheduled_event_id'] ?? data['id']) as String?;
    if (spaceId == null || eventId == null) return;
    switch (event.name) {
      case 'GUILD_SCHEDULED_EVENT_CREATE' || 'GUILD_SCHEDULED_EVENT_UPDATE':
        final mapped = _mapper.guildScheduledEvent(data);
        if (mapped == null) return;
        await _writeAndEmitScheduledEvent(mapped);
      case 'GUILD_SCHEDULED_EVENT_DELETE':
        await _cache.deleteGuildScheduledEvent(eventId);
        if (!_events.isClosed) {
          _events.add(
            GuildScheduledEventDeletedEvent(spaceId: spaceId, eventId: eventId),
          );
        }
      case 'GUILD_SCHEDULED_EVENT_USER_ADD' ||
          'GUILD_SCHEDULED_EVENT_USER_REMOVE':
        final cached = await _cache.readGuildScheduledEvents(spaceId);
        final matches = cached.where((item) => item.id == eventId);
        if (matches.isEmpty) return;
        final current = matches.first;
        final delta = event.name.endsWith('ADD') ? 1 : -1;
        final nextCount = current.interestedCount + delta;
        await _writeAndEmitScheduledEvent(
          current.copyWith(interestedCount: nextCount < 0 ? 0 : nextCount),
        );
    }
  }

  Future<void> _writeAndEmitScheduledEvent(GuildScheduledEvent event) async {
    await _cache.writeGuildScheduledEvent(event);
    if (!_events.isClosed) {
      _events.add(GuildScheduledEventUpsertedEvent(event));
    }
  }
}
