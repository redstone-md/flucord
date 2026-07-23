import 'chat_models.dart';

abstract interface class ChatCache {
  Future<ChatWorkspace?> readWorkspace();

  Future<void> writeWorkspace(ChatWorkspace workspace);

  Future<ChannelHistory> readChannelHistory(String channelId);

  Future<ChatMessage?> readMessage(String messageId);

  Future<ChannelHistory> readPinnedMessages(String channelId);

  Future<void> writeChannelHistory(
    ChannelHistory history, {
    bool replaceExisting = true,
  });

  Future<void> writeMessage(ChatMessage message, {Member? member});

  Future<void> writeMember(Member member);

  Future<void> writeSpace(CommunitySpace space);

  Future<void> writeCategory(ChannelCategory category);

  Future<void> replaceGuildEmojis(String spaceId, List<GuildEmoji> emojis);

  Future<void> replaceGuildStickers(
    String spaceId,
    List<GuildSticker> stickers,
  );

  Future<void> deleteMessage(String messageId);

  Future<void> writeChannel(ConversationChannel channel);

  Future<void> writeChannelActivity(ConversationChannel channel);

  Future<void> deleteChannel(String channelId);

  Future<void> deleteCategory(String categoryId);

  Future<void> close();
}
