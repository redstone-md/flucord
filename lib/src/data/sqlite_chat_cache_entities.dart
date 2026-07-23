part of 'sqlite_chat_cache.dart';

mixin _SqliteChatCacheEntities implements ChatCache {
  Database get _database;

  @override
  Future<void> writeMember(Member member) => _database.insert(
    'members',
    SqliteChatCache._memberToRow(member),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<void> writeCategory(ChannelCategory category) => _database.insert(
    'categories',
    SqliteChatCache._categoryToRow(category),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
