import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/chat_models.dart';

final class SqliteGuildEmojiStore {
  const SqliteGuildEmojiStore(this._database);

  final Database _database;

  Future<List<GuildEmoji>> readAll() async {
    final rows = await _database.query(
      'emojis',
      orderBy: 'space_id, name COLLATE NOCASE',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> writeAll(
    DatabaseExecutor executor,
    List<GuildEmoji> emojis,
  ) async {
    await executor.delete('emojis');
    final batch = executor.batch();
    for (final emoji in emojis) {
      batch.insert('emojis', _toRow(emoji));
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceForSpace(String spaceId, List<GuildEmoji> emojis) async {
    await _database.transaction((transaction) async {
      await transaction.delete(
        'emojis',
        where: 'space_id = ?',
        whereArgs: [spaceId],
      );
      final batch = transaction.batch();
      for (final emoji in emojis.where((emoji) => emoji.spaceId == spaceId)) {
        batch.insert('emojis', _toRow(emoji));
      }
      await batch.commit(noResult: true);
    });
  }

  static Map<String, Object?> _toRow(GuildEmoji emoji) => {
    'id': emoji.id,
    'space_id': emoji.spaceId,
    'name': emoji.name,
    'image_url': emoji.imageUrl,
    'animated': emoji.animated ? 1 : 0,
    'available': emoji.available ? 1 : 0,
  };

  static GuildEmoji _fromRow(Map<String, Object?> row) => GuildEmoji(
    id: row['id']! as String,
    spaceId: row['space_id']! as String,
    name: row['name']! as String,
    imageUrl: row['image_url'] as String?,
    animated: row['animated'] == 1,
    available: row['available'] == 1,
  );
}
