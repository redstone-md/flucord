import 'chat_models.dart';

abstract interface class MessageFlagRepository {
  Future<ChatMessage> setSuppressEmbeds({
    required String channelId,
    required String messageId,
    required bool suppress,
  });
}
