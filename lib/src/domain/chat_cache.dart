import 'chat_models.dart';

abstract interface class ChatCache {
  Future<ChatWorkspace?> readWorkspace();

  /// The workspace without its message history and without its members.
  ///
  /// Read this where only the navigation is wanted: which spaces, channels,
  /// categories and roles the account has, and what each channel has waiting.
  /// Decoding every cached message costs seconds on an account with a long
  /// history, and a caller that only looks up a channel never touches one.
  Future<ChatWorkspace?> readWorkspaceShell();

  Future<void> writeWorkspace(ChatWorkspace workspace);

  /// A channel's held messages, oldest first.
  ///
  /// [limit] keeps only the newest that many, which is what opening a channel
  /// wants: a channel with years of history then costs the same to open as a
  /// fresh one. [beforeMessageId] moves that window back to the messages sent
  /// before the one named, which is how the next page back is read. Omit both
  /// to read the channel in full.
  Future<ChannelHistory> readChannelHistory(
    String channelId, {
    int? limit,
    String? beforeMessageId,
  });

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

  Future<List<GuildScheduledEvent>> readGuildScheduledEvents(String spaceId);

  Future<void> replaceGuildScheduledEvents(
    String spaceId,
    List<GuildScheduledEvent> events,
  );

  Future<void> writeGuildScheduledEvent(GuildScheduledEvent event);

  Future<void> deleteGuildScheduledEvent(String eventId);

  Future<void> deleteMessage(String messageId);

  Future<void> writeChannel(ConversationChannel channel);

  Future<void> writeChannelActivity(ConversationChannel channel);

  Future<void> deleteChannel(String channelId);

  Future<void> deleteCategory(String categoryId);

  Future<void> close();
}
