part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryScheduledEvents implements ScheduledEventRepository {
  Future<void> _wait();

  @override
  Future<List<GuildScheduledEvent>> loadScheduledEvents(String spaceId) async {
    await _wait();
    if (spaceId != 'forge') return const [];
    final now = DateTime.now();
    return [
      GuildScheduledEvent(
        id: 'forge-review',
        spaceId: spaceId,
        channelId: 'forge-voice',
        name: 'Native client review',
        description: 'Walk through the current desktop build and open issues.',
        scheduledStartTime: now.add(const Duration(hours: 2)),
        scheduledEndTime: now.add(const Duration(hours: 3)),
        entityType: GuildScheduledEventEntityType.voice,
        status: GuildScheduledEventStatus.scheduled,
        interestedCount: 18,
      ),
      GuildScheduledEvent(
        id: 'forge-release',
        spaceId: spaceId,
        name: 'Release checkpoint',
        description: 'Final transport and packaging checkpoint.',
        location: 'Build room',
        scheduledStartTime: now.add(const Duration(days: 1)),
        scheduledEndTime: now.add(const Duration(days: 1, hours: 1)),
        entityType: GuildScheduledEventEntityType.external,
        status: GuildScheduledEventStatus.scheduled,
        interestedCount: 9,
      ),
    ];
  }

  @override
  Future<bool> setEventInterest({
    required String spaceId,
    required String eventId,
    required bool interested,
    String? exceptionId,
  }) async => true;
}
