part of 'chat_controller.dart';

extension ChatControllerForums on ChatController {
  Future<ConversationChannel?> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
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
        normalizedContent.isEmpty ||
        normalizedContent.length > 2000 ||
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
        appliedTagIds: List.unmodifiable(appliedTagIds),
      );
      _workspace = workspace!
          .upsertChannel(created.thread)
          .upsertMessage(created.initialMessage);
      _error = null;
      _notify();
      return created.thread;
    } catch (error) {
      _error = error;
      _notify();
      return null;
    }
  }
}
