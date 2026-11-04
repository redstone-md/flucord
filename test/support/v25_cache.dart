import 'dart:io';

import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Writes a cache file as version 25 left it, holding one DM [channelId] with
/// [recipientId], and returns its path. The test deletes it when it ends.
Future<String> writeV25DirectMessage({
  required String channelId,
  required String recipientId,
}) async {
  final directory = await Directory.systemTemp.createTemp('flucord-v25-');
  addTearDown(() => directory.delete(recursive: true));
  final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
  final legacy = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 25,
      onCreate: (database, _) async {
        for (final table in _shell) {
          await database.execute(table);
        }
      },
    ),
  );
  await legacy.insert('metadata', {'key': 'current_member_id', 'value': 'me'});
  await legacy.insert('spaces', {
    'id': CommunitySpace.directMessagesId,
    'name': 'Direct Messages',
    'monogram': 'DM',
    'color_value': 0xff59636a,
    'kind': SpaceKind.directMessages.index,
    'sort_index': 0,
  });
  await legacy.insert('channels', {
    'id': channelId,
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
    'recipient_id': recipientId,
    'sort_index': 0,
  });
  await legacy.close();
  return path;
}

/// The tables a workspace shell reads, as version 25 left them.
const _shell = [
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
