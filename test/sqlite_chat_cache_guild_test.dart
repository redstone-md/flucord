import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('a written guild is what a restart restores', () async {
    final cache = await _open();
    await _seedBaseWorkspace(cache);

    await cache.writeGuild(_auroraGuild());

    final restored = await cache.readWorkspace();
    expect(restored, isNotNull);
    expect(restored!.spaceOrNull('aurora')?.name, 'Aurora Labs');
    expect(restored.channelsFor('aurora').map((channel) => channel.name), [
      'general',
      'lab-notes',
    ]);
    expect(restored.categoriesFor('aurora').map((c) => c.name), ['Research']);
    expect(
      restored.roles.where((role) => role.spaceId == 'aurora').single.name,
      '@everyone',
    );
    // The account's own membership is what the permission model reads.
    expect(restored.memberOrNull('jack')?.membershipIn('aurora'), isNotNull);
    // The guild that was already there keeps its rows.
    expect(restored.spaceOrNull('forge'), isNotNull);
  });

  test('a deleted guild leaves no rows behind', () async {
    final cache = await _open();
    await _seedBaseWorkspace(cache);
    await cache.writeGuild(_auroraGuild());
    await cache.replaceGuildEmojis('aurora', [
      const GuildEmoji(id: 'emoji-1', spaceId: 'aurora', name: 'spark'),
    ]);

    await cache.deleteGuild('aurora');

    final restored = await cache.readWorkspace();
    expect(restored, isNotNull);
    expect(restored!.spaceOrNull('aurora'), isNull);
    expect(restored.channelsFor('aurora'), isEmpty);
    expect(restored.categoriesFor('aurora'), isEmpty);
    expect(restored.roles.where((role) => role.spaceId == 'aurora'), isEmpty);
    // The emoji of a left server must not resurrect under a missing space.
    expect(
      restored.emojis.where((emoji) => emoji.spaceId == 'aurora'),
      isEmpty,
    );
    // The base guild is untouched.
    expect(restored.spaceOrNull('forge'), isNotNull);
    expect(restored.channelsFor('forge'), isNotEmpty);
  });

  test(
    'a member shared between guilds keeps their other spaces on delete',
    () async {
      final cache = await _open();
      await _seedBaseWorkspace(cache);
      await cache.writeGuild(_auroraGuild());

      await cache.deleteGuild('aurora');

      final restored = await cache.readWorkspace();
      // The account was in forge first; leaving aurora keeps that row.
      expect(restored!.memberOrNull('jack'), isNotNull);
      expect(restored.memberOrNull('jack')!.membershipIn('aurora'), isNull);
    },
  );
}

Future<SqliteChatCache> _open() async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  addTearDown(cache.close);
  return cache;
}

Future<void> _seedBaseWorkspace(SqliteChatCache cache) => cache.writeWorkspace(
  ChatWorkspace(
    spaces: const [
      CommunitySpace(
        id: 'forge',
        name: 'Forge',
        monogram: 'FO',
        colorValue: 0xff456b5a,
      ),
    ],
    channels: const [
      ConversationChannel(
        id: 'forge-general',
        spaceId: 'forge',
        name: 'general',
        topic: '',
        kind: ChannelKind.text,
      ),
    ],
    members: const [
      Member(
        id: 'jack',
        displayName: 'Jack',
        initials: 'JA',
        role: 'member',
        presence: Presence.online,
        colorValue: 0xff456b5a,
        spaceIds: {'forge'},
      ),
    ],
    messages: const [],
    currentMemberId: 'jack',
  ),
);

JoinedGuild _auroraGuild() => JoinedGuild(
  space: CommunitySpace(
    id: 'aurora',
    name: 'Aurora Labs',
    monogram: 'AL',
    colorValue: 0xff486b70,
    iconUrl: 'https://cdn.discordapp.com/icons/aurora/aabbcc.webp',
  ),
  channels: [
    ConversationChannel(
      id: 'aurora-general',
      spaceId: 'aurora',
      name: 'general',
      topic: 'Say hello',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: 'aurora-notes',
      spaceId: 'aurora',
      name: 'lab-notes',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  categories: [
    ChannelCategory(
      id: 'aurora-cat',
      spaceId: 'aurora',
      name: 'Research',
      position: 0,
    ),
  ],
  roles: [
    CommunityRole(
      id: 'aurora',
      spaceId: 'aurora',
      name: '@everyone',
      position: 0,
    ),
  ],
  members: [
    Member(
      id: 'jack',
      displayName: 'Jack',
      initials: 'JA',
      role: 'member',
      presence: Presence.online,
      colorValue: 0xff486b70,
      spaceIds: {'forge', 'aurora'},
      membershipsBySpace: {'aurora': GuildMembership(roleIds: [])},
    ),
  ],
);
