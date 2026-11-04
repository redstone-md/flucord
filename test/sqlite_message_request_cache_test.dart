import 'dart:io';

import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _requestId = 'dm-request';
const _acceptedId = 'dm-accepted';

ConversationChannel _dm(
  String id, {
  bool request = false,
  DateTime? requestedAt,
}) => ConversationChannel(
  id: id,
  spaceId: CommunitySpace.directMessagesId,
  name: id,
  topic: '',
  kind: ChannelKind.text,
  recipientId: 'user-$id',
  isMessageRequest: request,
  messageRequestedAt: requestedAt,
);

void main() {
  setUpAll(sqfliteFfiInit);

  test('a cached message request stays a request, with its time', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final requestedAt = DateTime.utc(2026, 11, 3, 18, 30);

    await cache.writeWorkspace(
      ChatWorkspace(
        spaces: const [CommunitySpace.directMessages()],
        channels: [
          _dm(_requestId, request: true, requestedAt: requestedAt),
          _dm(_acceptedId),
        ],
        members: const [],
        messages: const [],
        currentMemberId: 'me',
      ),
    );
    final restored = (await cache.readWorkspace())!;

    final request = restored.channelById(_requestId);
    expect(request.isMessageRequest, isTrue);
    expect(request.messageRequestedAt, requestedAt);
    final accepted = restored.channelById(_acceptedId);
    expect(accepted.isMessageRequest, isFalse);
    expect(accepted.messageRequestedAt, isNull);
  });

  test('a channel cached before v26 opens as no request', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-message-request-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 25,
        onCreate: (database, _) async {
          for (final table in _v25Shell) {
            await database.execute(table);
          }
        },
      ),
    );
    await legacy.insert('metadata', {
      'key': 'current_member_id',
      'value': 'me',
    });
    await legacy.insert('spaces', {
      'id': CommunitySpace.directMessagesId,
      'name': 'Direct Messages',
      'monogram': 'DM',
      'color_value': 0xff59636a,
      'kind': SpaceKind.directMessages.index,
      'sort_index': 0,
    });
    await legacy.insert('channels', {
      'id': _acceptedId,
      'space_id': CommunitySpace.directMessagesId,
      'name': 'Jack',
      'topic': '',
      'kind': ChannelKind.text.index,
      'position': 0,
      'unread': 0,
      'mention_count': 0,
      'is_thread': 0,
      'is_archived': 0,
      'is_locked': 0,
      'available_tags_json': '[]',
      'applied_tag_ids_json': '[]',
      'recipient_id': 'user-1',
      'sort_index': 0,
    });
    await legacy.close();

    final cache = await SqliteChatCache.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final channel = (await cache.readWorkspaceShell())!.channelById(
      _acceptedId,
    );

    expect(channel.recipientId, 'user-1');
    expect(channel.isMessageRequest, isFalse);
    expect(channel.messageRequestedAt, isNull);
  });
}

/// The tables a workspace shell reads, as version 25 left them.
const _v25Shell = [
  'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  '''
  CREATE TABLE spaces (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    monogram TEXT NOT NULL,
    color_value INTEGER NOT NULL,
    icon_url TEXT,
    kind INTEGER NOT NULL,
    owner_id TEXT,
    requires_mfa INTEGER NOT NULL DEFAULT 0,
    premium_tier INTEGER NOT NULL DEFAULT 0,
    sort_index INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE categories (
    id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL,
    name TEXT NOT NULL,
    position INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE roles (
    id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL,
    name TEXT NOT NULL,
    position INTEGER NOT NULL,
    color_value INTEGER,
    permissions TEXT
  )
  ''',
  '''
  CREATE TABLE emojis (
    id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL,
    name TEXT NOT NULL,
    image_url TEXT,
    animated INTEGER NOT NULL,
    available INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE guild_stickers (
    id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    tags_json TEXT NOT NULL,
    format_type INTEGER NOT NULL,
    available INTEGER NOT NULL,
    url TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE channels (
    id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL,
    name TEXT NOT NULL,
    topic TEXT NOT NULL,
    kind INTEGER NOT NULL,
    position INTEGER NOT NULL,
    unread INTEGER NOT NULL,
    mention_count INTEGER NOT NULL,
    first_unread_message_id TEXT,
    last_message_id TEXT,
    parent_id TEXT,
    is_thread INTEGER NOT NULL,
    is_archived INTEGER NOT NULL,
    is_locked INTEGER NOT NULL,
    archive_timestamp TEXT,
    auto_archive_duration INTEGER,
    available_tags_json TEXT NOT NULL,
    applied_tag_ids_json TEXT NOT NULL,
    default_auto_archive_duration INTEGER,
    default_sort_order INTEGER,
    default_forum_layout INTEGER,
    recipient_id TEXT,
    permission_overwrites_json TEXT,
    rate_limit_per_user INTEGER NOT NULL DEFAULT 0,
    is_age_gated INTEGER NOT NULL DEFAULT 0,
    bitrate INTEGER,
    user_limit INTEGER,
    rtc_region TEXT,
    sort_index INTEGER NOT NULL
  )
  ''',
];
