import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('persists and atomically replaces guild sticker catalogs', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    await cache.writeWorkspace(_workspace([_sticker('old', 'Old signal')]));

    expect((await cache.readWorkspace())?.stickers.single.id, 'old');
    await cache.replaceGuildStickers('guild-1', [
      _sticker('new', 'New signal'),
    ]);

    final restored = await cache.readWorkspace();
    expect(restored?.stickers.single.id, 'new');
    expect(restored?.stickers.single.tags, ['signal', 'native']);
  });
}

ChatWorkspace _workspace(List<GuildSticker> stickers) => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [],
  members: const [],
  messages: const [],
  stickers: stickers,
  currentMemberId: 'bot-1',
);

GuildSticker _sticker(String id, String name) => GuildSticker(
  item: MessageSticker(
    id: id,
    name: name,
    format: StickerFormat.png,
    url: 'https://cdn.discordapp.com/stickers/$id.png',
  ),
  spaceId: 'guild-1',
  tags: const ['signal', 'native'],
  available: true,
);
