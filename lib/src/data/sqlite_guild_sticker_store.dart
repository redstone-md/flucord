import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/chat_models.dart';

final class SqliteGuildStickerStore {
  const SqliteGuildStickerStore(this._database);

  final Database _database;

  Future<List<GuildSticker>> readAll() async {
    final rows = await _database.query(
      'guild_stickers',
      orderBy: 'space_id, name COLLATE NOCASE',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> writeAll(
    DatabaseExecutor executor,
    List<GuildSticker> stickers,
  ) async {
    await executor.delete('guild_stickers');
    final batch = executor.batch();
    for (final sticker in stickers) {
      batch.insert('guild_stickers', _toRow(sticker));
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceForSpace(
    String spaceId,
    List<GuildSticker> stickers,
  ) async {
    await _database.transaction((transaction) async {
      await transaction.delete(
        'guild_stickers',
        where: 'space_id = ?',
        whereArgs: [spaceId],
      );
      final batch = transaction.batch();
      for (final sticker in stickers.where(
        (sticker) => sticker.spaceId == spaceId,
      )) {
        batch.insert('guild_stickers', _toRow(sticker));
      }
      await batch.commit(noResult: true);
    });
  }

  static Map<String, Object?> _toRow(GuildSticker sticker) => {
    'id': sticker.id,
    'space_id': sticker.spaceId,
    'name': sticker.name,
    'description': sticker.description,
    'tags_json': jsonEncode(sticker.tags),
    'format_type': sticker.item.format.discordValue,
    'available': sticker.available ? 1 : 0,
    'url': sticker.item.url,
  };

  static GuildSticker _fromRow(Map<String, Object?> row) => GuildSticker(
    item: MessageSticker(
      id: row['id']! as String,
      name: row['name']! as String,
      format: StickerFormat.fromDiscordValue(row['format_type']! as int),
      url: row['url']! as String,
    ),
    spaceId: row['space_id']! as String,
    description: row['description'] as String?,
    tags: (jsonDecode(row['tags_json']! as String) as List).cast<String>(),
    available: row['available'] == 1,
  );
}
