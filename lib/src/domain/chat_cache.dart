import 'chat_models.dart';

/// What the app keeps of an account between launches.
///
/// [writeMessage], [updateMessage], [writeMember], [writeSpace], [writeChannel],
/// [writeChannelActivity] and [deleteMessage] only queue their work and finish
/// at once, so nobody waits for the disk on them. The queue applies in order,
/// and flushes within a moment, on [flush] and on [close]. Every read finds the
/// writes asked for before it.
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

  /// Changes a held message in place, after the writes asked for before this.
  ///
  /// Nothing is written when the message is not held: not the message, and not
  /// [member]. Use this for a change to part of a message. It needs no read
  /// first, so it cannot wait for the disk.
  Future<void> updateMessage(
    String messageId,
    ChatMessage Function(ChatMessage held) change, {
    Member? member,
  });

  Future<void> writeMember(Member member);
  Future<void> writeSpace(CommunitySpace space);

  Future<void> writeCategory(ChannelCategory category);

  /// One guild the account gained, written whole: space, channels,
  /// categories, roles and members. What a restart restores.
  Future<void> writeGuild(JoinedGuild guild);

  /// One guild the account left, removed whole: its space, channels,
  /// categories, roles, the messages those channels held, and its emoji,
  /// stickers and scheduled events.
  Future<void> deleteGuild(String spaceId);

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

  /// Writes one [diff] in one transaction. A channel or server already held
  /// keeps its place, so an offline launch shows the same order. The diff's
  /// members are not written: the next full load brings them.
  Future<void> applyWorkspaceDiff(WorkspaceDiff diff);

  /// Removes everything held, for good, so that nothing of the account can be
  /// read back from the disk. Sign-out and a change of account call this.
  Future<void> clear();

  /// Finishes when every write asked for so far is on disk.
  Future<void> flush();

  Future<void> close();
}
