import 'dart:io';

import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/session_harness.dart';

const _userId = '100000000000000002';

Map<String, Object?> _user() => {
  'id': _userId,
  'username': 'freezz5126',
  'global_name': 'Freez',
};

ChatMessage _message() => ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: _userId,
  body: 'hi',
  sentAt: DateTime.utc(2026, 11, 4, 8),
);

Member _freez({String? username}) => Member(
  id: _userId,
  displayName: 'Freez',
  initials: 'F',
  role: 'Member',
  presence: Presence.offline,
  colorValue: 0xff456b5a,
  username: username,
);

/// A member keeps the username Discord sends with every user object, next to
/// the display name.
void main() {
  setUpAll(sqfliteFfiInit);
  final mapper = DiscordMapper();

  group('the username is read from', () {
    test('a message author', () {
      final author = mapper.messageAuthor({
        'id': '400000000000000001',
        'channel_id': '300000000000000001',
        'author': _user(),
        'content': 'hi',
        'timestamp': '2026-07-25T10:00:00+00:00',
      })!;

      expect(author.displayName, 'Freez');
      expect(author.username, 'freezz5126');
    });

    test('a guild member, under a nickname', () {
      final member = mapper.guildMember({
        'user': _user(),
        'nick': 'Freezy',
        'roles': <Object?>[],
      }, '200000000000000001');

      expect(member.displayName, 'Freezy');
      expect(member.username, 'freezz5126');
    });

    test('a member chunk', () {
      final members = mapper.membersFromChunk({
        'guild_id': '200000000000000001',
        'members': [
          {'user': _user(), 'roles': <Object?>[]},
        ],
      });

      expect(members.single.username, 'freezz5126');
    });

    test('a DM recipient', () {
      final dm = mapper.directMessage({
        'id': '300000000000000003',
        'type': 1,
        'recipients': [_user()],
      }, '100000000000000001')!;

      expect(dm.recipient.username, 'freezz5126');
    });
  });

  test('a user object with no username keeps the one known', () {
    final known = _freez(username: 'freezz5126');
    final workspace = ChatWorkspace(
      spaces: const [],
      channels: const [],
      members: [known],
      messages: const [],
      currentMemberId: 'me',
    );

    final merged = workspace.upsertMember(_freez());

    expect(merged.memberOrNull(_userId)?.username, 'freezz5126');
  });

  test('the cache keeps the username', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);

    await cache.writeMessage(
      _message(),
      member: _freez(username: 'freezz5126'),
    );
    await cache.writeMember(_freez());
    final restored = (await cache.readChannelHistory('channel-1')).members;

    expect(restored.single.username, 'freezz5126');
  });

  test('a member cached before v28 opens with no username', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-member-username-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 25,
        onCreate: (database, _) async {
          await database.execute(_v25Members);
          await database.execute(_v25Messages);
        },
      ),
    );
    await legacy.insert('members', {
      'id': _userId,
      'display_name': 'Freez',
      'initials': 'F',
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
      'author_id': _userId,
      'body': 'Before usernames',
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

    expect(author.displayName, 'Freez');
    expect(author.username, isNull);

    await cache.writeMember(_freez(username: 'freezz5126'));
    final updated = (await cache.readChannelHistory('channel-1')).members;
    expect(updated.single.username, 'freezz5126');
  });

  testSession('a presence with a whole user brings the username', (
    tester,
    session,
  ) async {
    await session.openChannel(
      SessionHarness.dmChannelId,
      space: 'direct-messages',
    );
    final panel = find.byKey(const ValueKey('dm-profile-panel'));
    Finder inPanel(String text) =>
        find.descendant(of: panel, matching: find.text(text));
    expect(inPanel('friend'), findsOneWidget);

    await session.dispatch('PRESENCE_UPDATE', {
      'status': 'online',
      'activities': <Object?>[],
      'user': {'id': SessionHarness.friendId, 'username': 'renamed'},
    });
    expect(inPanel('renamed'), findsOneWidget);

    // A presence that names the user by id alone keeps it.
    await session.dispatch('PRESENCE_UPDATE', {
      'status': 'idle',
      'activities': <Object?>[],
      'user': {'id': SessionHarness.friendId},
    });
    expect(inPanel('renamed'), findsOneWidget);
  }, size: const Size(1280, 720));
}

const _v25Members = '''
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
    memberships_json TEXT,
    is_bot INTEGER NOT NULL DEFAULT 0,
    clan_tag_json TEXT
  )
''';

const _v25Messages = '''
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
