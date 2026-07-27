import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/data/sqlite_chat_schema.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('SQLite v21 retains raw Discord message flags', () async {
    expect(SqliteChatSchema.version, 21);
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final flags =
        DiscordMessageFlag.suppressNotifications.bit |
        DiscordMessageFlag.hasThread.bit |
        (1 << 30);
    final message = ChatMessage(
      id: 'flagged-message',
      channelId: 'channel-1',
      authorId: 'bot-1',
      body: 'Quiet release',
      sentAt: DateTime.utc(2026, 7, 24, 8),
      flags: flags,
    );

    await cache.writeMessage(message);
    final restored = await cache.readMessage(message.id);

    expect(restored?.flags, flags);
    expect(restored?.suppressesNotifications, isTrue);
    expect(restored?.hasFlag(DiscordMessageFlag.hasThread), isTrue);
  });

  test('migrates v18 messages with safe flag defaults', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-message-flags-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 18,
        onCreate: (database, _) => _createV18Messages(database),
      ),
    );
    await legacy.insert('messages', {
      'id': 'v18-message',
      'channel_id': 'channel-1',
      'author_id': 'bot-1',
      'body': 'Before flags',
      'message_type': DiscordMessageType.defaultMessage.discordValue,
      'reference_message_id': null,
      'reference_channel_id': null,
      'reference_guild_id': null,
      'reference_type':
          DiscordMessageReferenceType.defaultReference.discordValue,
      'snapshots_json': '[]',
      'sent_at': DateTime.utc(2026, 7, 23).toIso8601String(),
      'is_edited': 0,
      'attachments_json': '[]',
      'reply_json': null,
      'reactions_json': '[]',
      'is_pinned': 0,
      'embeds_json': '[]',
      'mentions_current_member': 0,
      'poll_json': null,
      'stickers_json': '[]',
    });
    await legacy.close();

    final cache = await SqliteChatCache.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final restored = await cache.readMessage('v18-message');

    expect(restored?.body, 'Before flags');
    expect(restored?.flags, 0);
    expect(restored?.suppressesNotifications, isFalse);
  });
}

Future<void> _createV18Messages(Database database) => database.execute('''
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
    sent_at TEXT NOT NULL,
    is_edited INTEGER NOT NULL,
    attachments_json TEXT NOT NULL,
    reply_json TEXT,
    reactions_json TEXT NOT NULL,
    is_pinned INTEGER NOT NULL,
    embeds_json TEXT NOT NULL,
    mentions_current_member INTEGER NOT NULL,
    poll_json TEXT,
    stickers_json TEXT NOT NULL
  )
''');
