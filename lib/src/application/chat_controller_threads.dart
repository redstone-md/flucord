part of 'chat_controller.dart';

extension ChatControllerThreads on ChatController {
  Future<ConversationChannel?> createThreadFromMessage(
    ChatMessage message, {
    required String name,
    required int autoArchiveDurationMinutes,
  }) async {
    final normalizedName = name.trim();
    if (_workspace == null ||
        normalizedName.isEmpty ||
        normalizedName.length > 100 ||
        !const {60, 1440, 4320, 10080}.contains(autoArchiveDurationMinutes)) {
      return null;
    }
    try {
      final thread = await _repository.createThreadFromMessage(
        channelId: message.channelId,
        messageId: message.id,
        name: normalizedName,
        autoArchiveDurationMinutes: autoArchiveDurationMinutes,
      );
      _workspace = _workspace?.upsertChannel(thread);
      _error = null;
      _notify();
      return thread;
    } catch (error) {
      _error = error;
      _notify();
      return null;
    }
  }

  List<ConversationChannel> archivedThreadsFor(String parentChannelId) {
    final loaded = _archivedThreadState.threads[parentChannelId];
    if (loaded != null) return List.unmodifiable(loaded);
    return (_workspace?.channels ?? const <ConversationChannel>[])
        .where(
          (channel) =>
              channel.isThread &&
              channel.isArchived &&
              channel.parentId == parentChannelId,
        )
        .toList(growable: false);
  }

  bool isLoadingArchivedThreads(String parentChannelId) =>
      _archivedThreadState.loading.contains(parentChannelId);

  Object? archivedThreadsError(String parentChannelId) =>
      _archivedThreadState.errors[parentChannelId];

  bool canLoadMoreArchivedThreads(String parentChannelId) =>
      _archivedThreadState.hasMore[parentChannelId] ?? false;

  Future<void> loadArchivedThreads(
    String parentChannelId, {
    bool refresh = false,
  }) async {
    final repository = _repository is ArchivedThreadRepository
        ? _repository as ArchivedThreadRepository
        : null;
    if (repository == null ||
        _archivedThreadState.loading.contains(parentChannelId)) {
      return;
    }
    final initialized = _archivedThreadState.initialized.contains(
      parentChannelId,
    );
    if (!refresh &&
        initialized &&
        !canLoadMoreArchivedThreads(parentChannelId)) {
      return;
    }
    _archivedThreadState.loading.add(parentChannelId);
    _archivedThreadState.errors.remove(parentChannelId);
    _notify();
    try {
      final page = await repository.loadArchivedThreads(
        parentChannelId,
        before: refresh ? null : _archivedThreadState.before[parentChannelId],
      );
      final previous = refresh
          ? const <ConversationChannel>[]
          : _archivedThreadState.threads[parentChannelId] ??
                const <ConversationChannel>[];
      final byId = {for (final thread in previous) thread.id: thread};
      for (final thread in page.threads) {
        byId[thread.id] = thread;
        _workspace = _workspace?.upsertChannel(thread);
      }
      _archivedThreadState.threads[parentChannelId] = byId.values.toList();
      _archivedThreadState.hasMore[parentChannelId] = page.hasMore;
      _archivedThreadState.before[parentChannelId] = page.nextBefore;
      _archivedThreadState.initialized.add(parentChannelId);
    } catch (error) {
      _archivedThreadState.errors[parentChannelId] = error;
    } finally {
      _archivedThreadState.loading.remove(parentChannelId);
      if (!_disposed) _notify();
    }
  }
}

final class _ArchivedThreadState {
  final Map<String, List<ConversationChannel>> threads = {};
  final Map<String, DateTime?> before = {};
  final Map<String, bool> hasMore = {};
  final Map<String, Object> errors = {};
  final Set<String> loading = {};
  final Set<String> initialized = {};

  void clear() {
    threads.clear();
    before.clear();
    hasMore.clear();
    errors.clear();
    loading.clear();
    initialized.clear();
  }
}
