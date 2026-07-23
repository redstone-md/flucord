import 'chat_models.dart';

abstract interface class ChatRepository {
  Future<ChatWorkspace> loadWorkspace();

  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
  });
}
