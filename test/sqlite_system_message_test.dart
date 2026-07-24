import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/data/sqlite_chat_schema.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('SQLite retains system type and message reference', () async {
    expect(SqliteChatSchema.version, 19);
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final message = ChatMessage(
      id: 'system-1',
      channelId: 'channel-1',
      authorId: 'user-1',
      body: 'release-checklist',
      sentAt: DateTime.utc(2026, 7, 24, 6),
      type: DiscordMessageType.threadCreated,
      reference: const MessageReference(
        messageId: 'message-1',
        channelId: 'thread-1',
      ),
    );

    await cache.writeMessage(message);
    final restored = await cache.readMessage(message.id);

    expect(restored?.type, DiscordMessageType.threadCreated);
    expect(restored?.reference?.messageId, 'message-1');
    expect(restored?.reference?.channelId, 'thread-1');
    expect(restored?.isSystem, isTrue);
  });

  test('migrates v16 messages with safe system-message defaults', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-system-message-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 16,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE messages (
              id TEXT PRIMARY KEY,
              channel_id TEXT NOT NULL,
              author_id TEXT NOT NULL,
              body TEXT NOT NULL,
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
        },
      ),
    );
    await legacy.insert('messages', {
      'id': 'legacy-message',
      'channel_id': 'legacy-channel',
      'author_id': 'legacy-author',
      'body': 'before v17',
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
    final restored = await cache.readMessage('legacy-message');

    expect(restored?.type, DiscordMessageType.defaultMessage);
    expect(restored?.reference, isNull);
  });
}
