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

  /// Says whether this account is interested in an event.
  ///
  /// The count is not touched here. Discord echoes the change back as a
  /// dispatch that moves it, and two places counting the same thing is how a
  /// count ends up permanently wrong by one.
  Future<bool> setEventInterest(
    GuildScheduledEvent event, {
    required bool interested,
  }) async {
    final repository = _repository;
    if (repository is! ScheduledEventRepository) return false;
    final scheduledRepository = repository as ScheduledEventRepository;
    try {
      return await scheduledRepository.setEventInterest(
        spaceId: event.spaceId,
        eventId: event.id,
        interested: interested,
      );
    } catch (error) {
      _scheduledEventErrors[event.spaceId] = error;
      _notify();
      return false;
    }
  }

  /// Creates an event and shows it without waiting for the dispatch.
  ///
  /// Unlike the RSVP count, this is the whole object as the server stored it,
  /// so putting it in the list is repeating Discord rather than guessing at
  /// it. The dispatch that follows replaces the same row.
  Future<GuildScheduledEvent?> createScheduledEvent(
    String spaceId,
    GuildScheduledEventDraft draft,
  ) async {
    final repository = _repository;
    if (repository is! ScheduledEventRepository) return null;
    final scheduledRepository = repository as ScheduledEventRepository;
    try {
      final created = await scheduledRepository.createScheduledEvent(
        spaceId: spaceId,
        draft: draft,
      );
      if (created != null) {
        _upsertScheduledEvent(created);
        _notify();
      }
      return created;
    } catch (error) {
      _scheduledEventErrors[spaceId] = error;
      _notify();
      return null;
    }
  }

  Future<GuildScheduledEvent?> editScheduledEvent(
    GuildScheduledEvent event,
    GuildScheduledEventEdit edit,
  ) async {
    final repository = _repository;
    if (repository is! ScheduledEventRepository) return null;
    final scheduledRepository = repository as ScheduledEventRepository;
    try {
      final updated = await scheduledRepository.editScheduledEvent(
        spaceId: event.spaceId,
        eventId: event.id,
        edit: edit,
      );
      if (updated != null) {
        _upsertScheduledEvent(updated);
        _notify();
      }
      return updated;
    } catch (error) {
      _scheduledEventErrors[event.spaceId] = error;
      _notify();
      return null;
    }
  }

  Future<bool> deleteScheduledEvent(GuildScheduledEvent event) async {
    final repository = _repository;
    if (repository is! ScheduledEventRepository) return false;
    final scheduledRepository = repository as ScheduledEventRepository;
    try {
      final deleted = await scheduledRepository.deleteScheduledEvent(
        spaceId: event.spaceId,
        eventId: event.id,
      );
      if (deleted) {
        _deleteScheduledEvent(event.spaceId, event.id);
        _notify();
      }
      return deleted;
    } catch (error) {
      _scheduledEventErrors[event.spaceId] = error;
      _notify();
      return false;
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
