import 'chat_models.dart';

abstract interface class ChatCache {
  Future<ChatWorkspace?> readWorkspace();

  Future<void> writeWorkspace(ChatWorkspace workspace);

  Future<ChannelHistory> readChannelHistory(String channelId);

  Future<ChatMessage?> readMessage(String messageId);

  Future<ChannelHistory> readPinnedMessages(String channelId);

  Future<void> writeChannelHistory(ChannelHistory history);

  Future<void> writeMessage(ChatMessage message, {Member? member});

  Future<void> writeMember(Member member);

  Future<void> deleteMessage(String messageId);

  Future<void> writeChannel(ConversationChannel channel);

  Future<void> deleteChannel(String channelId);

  Future<void> close();
}
