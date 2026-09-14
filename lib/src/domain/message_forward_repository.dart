import 'chat_models.dart';

abstract interface class MessageForwardRepository {
  Future<ChatMessage> forwardMessage({
    required String sourceChannelId,
    required String sourceMessageId,
    required String targetChannelId,
  });
}
