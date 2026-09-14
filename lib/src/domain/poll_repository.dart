import 'chat_models.dart';

abstract interface class PollRepository {
  Future<ChatMessage> createPoll({
    required String channelId,
    required String authorId,
    required PendingPoll poll,
  });

  Future<ChatMessage> endPoll({
    required String channelId,
    required String messageId,
  });
}
