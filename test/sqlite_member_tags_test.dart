import 'dart:io';

import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _authorId = 'bot-1';

ChatMessage _message() => ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: _authorId,
  body: 'Beep',
  sentAt: DateTime.utc(2026, 11, 4, 8),
);

void main() {
  setUpAll(sqfliteFfiInit);

  test('a cached member keeps the bot flag and the clan tag', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);

    await cache.writeMessage(
      _message(),
      member: const Member(
        id: _authorId,
        displayName: 'Helper',
        initials: 'H',
        role: 'Member',
        presence: Presence.offline,
        colorValue: 0xff456b5a,
        tags: MemberTags(
          isBot: true,
          clanTag: ClanTag(
            tag: 'CODE',
            guildId: 'guild-9',
            badgeUrl: 'https://cdn.discordapp.com/clan-badges/guild-9/b.webp',
          ),
        ),
      ),
    );
    final restored = (await cache.readChannelHistory('channel-1')).members;

    final author = restored.single;
    expect(author.isBot, isTrue);
    expect(author.clanTag?.tag, 'CODE');
    expect(author.clanTag?.guildId, 'guild-9');
    expect(
      author.clanTag?.badgeUrl,
      'https://cdn.discordapp.com/clan-badges/guild-9/b.webp',
    );
  });

  test(
    'a member written without a word on the clan keeps the stored tag',
    () async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(cache.close);
      Member helper(MemberTags tags) => Member(
        id: _authorId,
        displayName: 'Helper',
        initials: 'H',
        role: 'Member',
        presence: Presence.offline,
        colorValue: 0xff456b5a,
        tags: tags,
      );

      await cache.writeMessage(
        _message(),
        member: helper(
          const MemberTags(
            clanTag: ClanTag(tag: 'CODE', guildId: 'guild-9'),
          ),
        ),
      );
      await cache.writeMember(helper(const MemberTags.clanTagUnsaid()));
      final kept = (await cache.readChannelHistory('channel-1')).members.single;

      await cache.writeMember(helper(const MemberTags()));
      final cleared = (await cache.readChannelHistory('channel-1')).members;

      expect(kept.clanTag?.tag, 'CODE');
      expect(cleared.single.clanTag, isNull);
    },
  );

  test('a later write without the bot flag keeps it', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    Member helper(MemberTags tags) => Member(
      id: _authorId,
      displayName: 'Helper',
      initials: 'H',
      role: 'Member',
      presence: Presence.offline,
      colorValue: 0xff456b5a,
      tags: tags,
    );

    await cache.writeMessage(
      _message(),
      member: helper(const MemberTags(isBot: true)),
    );
    await cache.writeMemberTags(_authorId, const MemberTags.clanTagUnsaid());
    await cache.writeMember(helper(const MemberTags()));
    final author = (await cache.readChannelHistory('channel-1')).members;

    expect(author.single.isBot, isTrue);
  });

  test('a member cached before v25 opens as a person with no tag', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-member-tags-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 24,
        onCreate: (database, _) async {
          await database.execute(_v24Members);
          await database.execute(_v24Messages);
        },
      ),
    );
    await legacy.insert('members', {
      'id': _authorId,
      'display_name': 'Helper',
      'initials': 'H',
      'role': 'Member',
      'presence': Presence.offline.index,
      'color_value': 0xff456b5a,
      'space_ids_json': '[]',
      'roles_by_space_json': '{}',
      'avatar_urls_by_space_json': '{}',
    });
    await legacy.insert('messages', {
      'id': 'message-1',
      'channel_id': 'channel-1',
      'author_id': _authorId,
      'body': 'Before tags',
      'message_type': 0,
      'reference_type': 0,
      'snapshots_json': '[]',
      'flags': 0,
      'sent_at': DateTime.utc(2026, 11, 3).toIso8601String(),
      'is_edited': 0,
      'attachments_json': '[]',
      'reactions_json': '[]',
      'is_pinned': 0,
      'embeds_json': '[]',
      'mentions_current_member': 0,
      'stickers_json': '[]',
    });
    await legacy.close();

    final cache = await SqliteChatCache.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final author = (await cache.readChannelHistory('channel-1')).members.single;

    expect(author.displayName, 'Helper');
    expect(author.isBot, isFalse);
    expect(author.clanTag, isNull);
  });
}

const _v24Members = '''
  CREATE TABLE members (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    initials TEXT NOT NULL,
    role TEXT NOT NULL,
    presence INTEGER NOT NULL,
    color_value INTEGER NOT NULL,
    space_ids_json TEXT NOT NULL,
    roles_by_space_json TEXT NOT NULL,
    avatar_url TEXT,
    avatar_urls_by_space_json TEXT NOT NULL,
    memberships_json TEXT
  )
''';

const _v24Messages = '''
  CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    channel_id TEXT NOT NULL,
    author_id TEXT NOT NULL,
    body TEXT NOT NULL,
    message_type INTEGER NOT NULL,
    reference_message_id TEXT,
    reference_channel_id TEXT,
    reference_guild_id TEXT,
    reference_type INTEGER NOT NULL,
    snapshots_json TEXT NOT NULL,
    flags INTEGER NOT NULL,
    sent_at TEXT NOT NULL,
    is_edited INTEGER NOT NULL,
    attachments_json TEXT NOT NULL,
    reply_json TEXT,
    reactions_json TEXT NOT NULL,
    is_pinned INTEGER NOT NULL,
    embeds_json TEXT NOT NULL,
    mentions_current_member INTEGER NOT NULL,
    poll_json TEXT,
    stickers_json TEXT NOT NULL,
    is_text_to_speech INTEGER NOT NULL DEFAULT 0,
    components_json TEXT NOT NULL DEFAULT '[]',
    mentions_everyone INTEGER NOT NULL DEFAULT 0
  )
''';
