part of 'chat_controller.dart';

extension ChatControllerScheduledEvents on ChatController {
  List<GuildScheduledEvent> scheduledEventsFor(String spaceId) =>
      List.unmodifiable(_scheduledEventsBySpace[spaceId] ?? const []);

  bool isLoadingScheduledEvents(String spaceId) =>
      _loadingScheduledEventSpaces.contains(spaceId);

  Object? scheduledEventsError(String spaceId) =>
      _scheduledEventErrors[spaceId];

  Future<void> _loadScheduledEventsForWorkspace() async {
    final workspace = _workspace;
    if (workspace == null) return;
    await Future.wait(
      workspace.spaces
          .where((space) => !space.isDirectMessages)
          .map((space) => loadScheduledEvents(space.id, notify: false)),
    );
  }

  Future<void> loadScheduledEvents(String spaceId, {bool notify = true}) async {
    if (!_loadingScheduledEventSpaces.add(spaceId)) return;
    _scheduledEventErrors.remove(spaceId);
    if (notify) _notify();
    try {
      final repository = _repository;
      if (repository is! ScheduledEventRepository) {
        _scheduledEventsBySpace[spaceId] = const [];
        return;
      }
      final scheduledRepository = repository as ScheduledEventRepository;
      final events = await scheduledRepository.loadScheduledEvents(spaceId);
      _scheduledEventsBySpace[spaceId] =
          events.where((event) => !event.isTerminal).toList(growable: false)
            ..sort(GuildScheduledEvent.compareForDisplay);
    } catch (error) {
      _scheduledEventErrors[spaceId] = error;
    } finally {
      _loadingScheduledEventSpaces.remove(spaceId);
      if (notify) _notify();
    }
  }

  void _upsertScheduledEvent(GuildScheduledEvent event) {
    final current = _scheduledEventsBySpace[event.spaceId] ?? const [];
    final next = [
      ...current.where((item) => item.id != event.id),
      if (!event.isTerminal) event,
    ]..sort(GuildScheduledEvent.compareForDisplay);
    _scheduledEventsBySpace[event.spaceId] = next;
  }

  void _deleteScheduledEvent(String spaceId, String eventId) {
    _scheduledEventsBySpace[spaceId] = (_scheduledEventsBySpace[spaceId] ?? [])
        .where((event) => event.id != eventId)
        .toList(growable: false);
  }
}
