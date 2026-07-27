part of 'chat_controller.dart';

extension ChatControllerForums on ChatController {
  Future<void> loadForumPostPreview(String channelId) async {
    final workspace = _workspace;
    final channel = workspace?.channelOrNull(channelId);
    final parent = channel?.parentId == null
        ? null
        : workspace?.channelOrNull(channel!.parentId!);
    if (workspace == null ||
        channel == null ||
        !channel.isThread ||
        (parent?.kind != ChannelKind.forum &&
            parent?.kind != ChannelKind.media) ||
        workspace.messagesFor(channelId).isNotEmpty ||
        _loadingChannels.contains(channelId) ||
        _loadedChannels.contains(channelId)) {
      return;
    }
    _loadingChannels.add(channelId);
    try {
      final page = await _repository.loadChannelHistory(channelId);
      _workspace = _workspace?.mergeInitialHistory(
        page.history,
        retainExisting: true,
      );
      _loadedChannels.add(channelId);
      _setHistoryExhausted(channelId, !page.hasMore);
    } on Object {
      // Preview loading is opportunistic; opening the post retries visibly.
    } finally {
      _loadingChannels.remove(channelId);
      if (!_disposed) _notify();
    }
  }

  Future<ConversationChannel?> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    List<PendingAttachment> attachments = const [],
    List<String> appliedTagIds = const [],
  }) async {
    final workspace = _workspace;
    final repository = _repository is ForumPostRepository
        ? _repository as ForumPostRepository
        : null;
    final parent = workspace?.channelOrNull(channelId);
    final normalizedName = name.trim();
    final normalizedContent = content.trim();
    final availableTagIds = parent?.availableTags.map((tag) => tag.id).toSet();
    if (repository == null ||
        parent == null ||
        (parent.kind != ChannelKind.forum &&
            parent.kind != ChannelKind.media) ||
        normalizedName.isEmpty ||
        normalizedName.length > 100 ||
        (normalizedContent.isEmpty && attachments.isEmpty) ||
        normalizedContent.length > 2000 ||
        attachments.length > PendingAttachment.maxCount ||
        attachments.map((item) => item.path).toSet().length !=
            attachments.length ||
        appliedTagIds.length > 5 ||
        appliedTagIds.toSet().length != appliedTagIds.length ||
        !const {60, 1440, 4320, 10080}.contains(autoArchiveDurationMinutes) ||
        appliedTagIds.any((id) => !availableTagIds!.contains(id))) {
      return null;
    }
    try {
      final created = await repository.createForumPost(
        channelId: channelId,
        name: normalizedName,
        content: normalizedContent,
        autoArchiveDurationMinutes: autoArchiveDurationMinutes,
        attachments: List.unmodifiable(attachments),
        appliedTagIds: List.unmodifiable(appliedTagIds),
      );
      // The post's own opening message is the newest thing in it, so the
      // pointer unread is measured against is set before the thread is stored
      // rather than being back-filled by the upsert below.
      final thread = created.thread.withLatestMessage(
        created.initialMessage.id,
      );
      _workspace = workspace!
          .upsertChannel(thread)
          .upsertMessage(created.initialMessage);
      _error = null;
      _notify();
      return thread;
    } catch (error) {
      _error = error;
      _notify();
      return null;
    }
  }
}
