import 'chat_models.dart';

abstract interface class ChatCache {
  Future<ChatWorkspace?> readWorkspace();

  Future<void> writeWorkspace(ChatWorkspace workspace);

  Future<ChannelHistory> readChannelHistory(String channelId);

  Future<void> writeChannelHistory(ChannelHistory history);

  Future<void> writeMessage(ChatMessage message, {Member? member});

  Future<void> close();
}
