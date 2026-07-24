part of 'sqlite_chat_cache.dart';

mixin _SqliteChatCacheExpressions implements ChatCache {
  Database get _database;

  Future<(List<GuildEmoji>, List<GuildSticker>)>
  _readGuildExpressions() async => (
    await SqliteGuildEmojiStore(_database).readAll(),
    await SqliteGuildStickerStore(_database).readAll(),
  );

  Future<void> _writeGuildExpressions(
    DatabaseExecutor executor,
    ChatWorkspace workspace,
  ) async {
    await SqliteGuildEmojiStore(_database).writeAll(executor, workspace.emojis);
    await SqliteGuildStickerStore(
      _database,
    ).writeAll(executor, workspace.stickers);
  }

  @override
  Future<void> replaceGuildEmojis(String spaceId, List<GuildEmoji> emojis) =>
      SqliteGuildEmojiStore(_database).replaceForSpace(spaceId, emojis);

  @override
  Future<void> replaceGuildStickers(
    String spaceId,
    List<GuildSticker> stickers,
  ) => SqliteGuildStickerStore(_database).replaceForSpace(spaceId, stickers);

  @override
  Future<List<GuildScheduledEvent>> readGuildScheduledEvents(String spaceId) =>
      SqliteGuildScheduledEventStore(_database).readForSpace(spaceId);

  @override
  Future<void> replaceGuildScheduledEvents(
    String spaceId,
    List<GuildScheduledEvent> events,
  ) => SqliteGuildScheduledEventStore(
    _database,
  ).replaceForSpace(spaceId, events);

  @override
  Future<void> writeGuildScheduledEvent(GuildScheduledEvent event) =>
      SqliteGuildScheduledEventStore(_database).write(event);

  @override
  Future<void> deleteGuildScheduledEvent(String eventId) =>
      SqliteGuildScheduledEventStore(_database).delete(eventId);
}
