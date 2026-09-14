import 'chat_models.dart';

final class CreatedForumPost {
  const CreatedForumPost({required this.thread, required this.initialMessage});

  final ConversationChannel thread;
  final ChatMessage initialMessage;
}

abstract interface class ForumPostRepository {
  Future<CreatedForumPost> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    List<PendingAttachment> attachments = const [],
    List<String> appliedTagIds = const [],
  });
}
