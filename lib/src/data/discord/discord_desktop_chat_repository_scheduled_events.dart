part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryScheduledEvents
    implements ScheduledEventRepository {
  DiscordDesktopApiClient get _api;
  DiscordMapper get _mapper;
  DiscordScheduledEvents get _scheduledEvents;

  @override
  Future<List<GuildScheduledEvent>> loadScheduledEvents(String spaceId) =>
      _scheduledEvents.load(
        spaceId,
        () => _api.getGuildScheduledEvents(spaceId),
      );

  @override
  Future<List<GuildScheduledEventAttendee>> loadEventAttendees({
    required String spaceId,
    required String eventId,
    int limit = 100,
  }) async {
    final payloads = await _api.getGuildScheduledEventUsers(
      guildId: spaceId,
      eventId: eventId,
      limit: limit,
    );
    return [for (final payload in payloads) ?_readAttendee(payload)];
  }

  /// Reads one row of the interested list.
  ///
  /// The nickname a server knows somebody by wins over their global name,
  /// because that is the name everybody else in that server sees them under.
  static GuildScheduledEventAttendee? _readAttendee(
    Map<String, Object?> payload,
  ) {
    final user = payload['user'];
    if (user is! Map) return null;
    final fields = user.cast<String, Object?>();
    final id = fields['id'];
    if (id is! String || id.isEmpty) return null;
    final member = payload['member'] is Map
        ? (payload['member']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final nickname = member['nick'];
    final global = fields['global_name'];
    final username = fields['username'];
    return GuildScheduledEventAttendee(
      userId: id,
      displayName: switch ((nickname, global, username)) {
        (final String nick, _, _) when nick.isNotEmpty => nick,
        (_, final String name, _) when name.isNotEmpty => name,
        (_, _, final String name) when name.isNotEmpty => name,
        _ => '',
      },
    );
  }

  @override
  Future<GuildScheduledEvent?> createScheduledEvent({
    required String spaceId,
    required GuildScheduledEventDraft draft,
  }) async {
    if (!draft.isValid) return null;
    final payload = await _api.createGuildScheduledEvent(
      guildId: spaceId,
      body: GuildScheduledEventEdit.encodeDraft(draft),
    );
    return _mapper.guildScheduledEvent(payload, fallbackSpaceId: spaceId);
  }

  @override
  Future<GuildScheduledEvent?> editScheduledEvent({
    required String spaceId,
    required String eventId,
    required GuildScheduledEventEdit edit,
  }) async {
    if (edit.isEmpty) return null;
    final payload = await _api.editGuildScheduledEvent(
      guildId: spaceId,
      eventId: eventId,
      body: edit.toJson(),
    );
    return _mapper.guildScheduledEvent(payload, fallbackSpaceId: spaceId);
  }

  @override
  Future<bool> deleteScheduledEvent({
    required String spaceId,
    required String eventId,
  }) async {
    try {
      await _api.deleteGuildScheduledEvent(guildId: spaceId, eventId: eventId);
      return true;
    } on DiscordApiException catch (error) {
      // An event somebody else already deleted, or one this account may not
      // manage, is refused. Neither is a fault here.
      if (error.statusCode == 403 || error.statusCode == 404) return false;
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
      // That is an answer about the event, not a fault here.
      if (error.statusCode == 400 || error.statusCode == 403) return false;
      rethrow;
    }
    // The count moves when Discord echoes the change back. Patching it here
    // as well is how a count ends up permanently wrong by one.
    return true;
  }
}
