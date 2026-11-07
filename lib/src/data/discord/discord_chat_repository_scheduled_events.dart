part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryScheduledEvents
    implements ScheduledEventRepository {
  DiscordApiClient get _api;
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
  }) async => const [];

  @override
  Future<GuildScheduledEvent?> createScheduledEvent({
    required String spaceId,
    required GuildScheduledEventDraft draft,
  }) async => null;

  @override
  Future<GuildScheduledEvent?> editScheduledEvent({
    required String spaceId,
    required String eventId,
    required GuildScheduledEventEdit edit,
  }) async => null;

  @override
  Future<bool> deleteScheduledEvent({
    required String spaceId,
    required String eventId,
  }) async => false;

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
}
