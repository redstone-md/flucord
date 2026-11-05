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

  /// Every thread under [parentId] the workspace holds, the one with the
  /// newest message first, as Discord lists them. In a forum these are its
  /// posts.
  List<ConversationChannel> threadsFor(String parentId) {
    String activity(ConversationChannel thread) =>
        thread.lastMessageId ?? thread.id;
    return (_workspace?.channels ?? const <ConversationChannel>[])
        .where((channel) => channel.isThread && channel.parentId == parentId)
        .toList()
      ..sort((a, b) => DiscordSnowflake.compare(activity(b), activity(a)));
  }

  bool isLoadingThreads(String parentId) =>
      _threadPages.loading.containsKey(parentId);

  Object? threadsError(String parentId) => _threadPages.errors[parentId];

  bool canLoadMoreThreads(String parentId) =>
      _threadPages.hasMore[parentId] ?? false;

  /// Loads the next page of the threads under [parentId], or the first one
  /// again when [refresh] is set or [tagIds] names other tags than the last
  /// load. The gateway only sends a user the threads they joined, so this is
  /// how the others arrive.
  Future<void> loadThreads(
    String parentId, {
    bool refresh = false,
    Set<String>? tagIds,
  }) async {
    final repository = _repository is ThreadListRepository
        ? _repository as ThreadListRepository
        : null;
    if (repository == null) return;
    final pages = _threadPages;
    final tags = tagIds ?? pages.tags[parentId] ?? const <String>{};
    final fresh =
        refresh || !setEquals(tags, pages.tags[parentId] ?? const <String>{});
    if (!fresh &&
        (pages.loading.containsKey(parentId) ||
            (pages.initialized.contains(parentId) &&
                !canLoadMoreThreads(parentId)))) {
      return;
    }
    final offset = fresh ? 0 : pages.loaded[parentId] ?? 0;
    // A newer load for the same parent, with other tags say, outlives this
    // one: its answer is then dropped rather than folded in.
    final request = Object();
    pages.loading[parentId] = request;
    pages.tags[parentId] = tags;
    pages.errors.remove(parentId);
    _notify();
    bool current() => identical(pages.loading[parentId], request);
    try {
      final page = await repository.loadThreads(
        parentId,
        offset: offset,
        tagIds: tags,
      );
      if (!current()) return;
      var workspace = _workspace;
      for (final thread in page.threads) {
        workspace = workspace?.upsertChannel(thread);
      }
      for (final message in page.firstMessages) {
        workspace = workspace?.mergeInitialHistory(
          ChannelHistory(
            channelId: message.channelId,
            messages: [message],
            members: const [],
          ),
          retainExisting: true,
        );
      }
      _workspace = workspace;
      pages.loaded[parentId] = offset + page.threads.length;
      pages.hasMore[parentId] = page.hasMore;
      pages.initialized.add(parentId);
    } catch (error) {
      if (current()) pages.errors[parentId] = error;
    } finally {
      if (current()) {
        pages.loading.remove(parentId);
        if (!_disposed) _notify();
      }
    }
  }
}

/// How far the thread list under each parent channel has been loaded.
final class _ThreadPages {
  /// How many threads the loads so far returned, which is where the next
  /// page starts.
  final Map<String, int> loaded = {};

  /// The tags the loads were filtered by.
  final Map<String, Set<String>> tags = {};
  final Map<String, bool> hasMore = {};
  final Map<String, Object> errors = {};

  /// The load in flight for each parent.
  final Map<String, Object> loading = {};
  final Set<String> initialized = {};

  void clear() {
    loaded.clear();
    tags.clear();
    hasMore.clear();
    errors.clear();
    loading.clear();
    initialized.clear();
  }
}
