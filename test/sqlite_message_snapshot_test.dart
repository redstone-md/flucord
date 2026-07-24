import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/data/sqlite_chat_schema.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/message_embed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('SQLite retains forward references and snapshots', () async {
    expect(SqliteChatSchema.version, 19);
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final message = ChatMessage(
      id: 'forward-1',
      channelId: 'target-channel',
      authorId: 'bot-1',
      body: '',
      sentAt: DateTime.utc(2026, 7, 24, 8),
      reference: const MessageReference(
        type: DiscordMessageReferenceType.forward,
        messageId: 'source-1',
        channelId: 'source-channel',
        guildId: 'guild-1',
      ),
      snapshots: [
        MessageSnapshot(
          type: DiscordMessageType.defaultMessage,
          body: 'Original',
          sentAt: DateTime.utc(2026, 7, 23, 18),
          editedAt: DateTime.utc(2026, 7, 23, 18, 5),
          flags: 16384,
          attachments: const [
            MessageAttachment(
              id: 'attachment-1',
              fileName: 'notes.txt',
              url: 'https://cdn.discordapp.com/notes.txt',
              size: 42,
            ),
          ],
          embeds: [MessageEmbed(type: 'rich', title: 'Release')],
          mentionedUserIds: const {'user-1'},
          mentionedRoleIds: const {'role-1'},
          components: const [MessageComponentSnapshot('{"type":1}')],
        ),
      ],
    );

    await cache.writeMessage(message);
    final restored = await cache.readMessage(message.id);

    expect(restored?.isForwarded, isTrue);
    expect(restored?.reference?.guildId, 'guild-1');
    final snapshot = restored!.snapshots.single;
    expect(snapshot.body, 'Original');
    expect(snapshot.flags, 16384);
    expect(snapshot.attachments.single.fileName, 'notes.txt');
    expect(snapshot.embeds.single.title, 'Release');
    expect(snapshot.mentionedUserIds, {'user-1'});
    expect(snapshot.mentionedRoleIds, {'role-1'});
    expect(snapshot.components.single.payloadJson, '{"type":1}');
  });

  test('migrates v17 messages with safe snapshot defaults', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-message-snapshot-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 17,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE messages (
              id TEXT PRIMARY KEY,
              channel_id TEXT NOT NULL,
              author_id TEXT NOT NULL,
              body TEXT NOT NULL,
              message_type INTEGER NOT NULL,
              reference_message_id TEXT,
              reference_channel_id TEXT,
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
      'id': 'v17-message',
      'channel_id': 'channel-1',
      'author_id': 'author-1',
      'body': 'before snapshots',
      'message_type': DiscordMessageType.reply.discordValue,
      'reference_message_id': 'source-message',
      'reference_channel_id': 'source-channel',
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
    final restored = await cache.readMessage('v17-message');

    expect(restored?.type, DiscordMessageType.reply);
    expect(restored?.reference?.messageId, 'source-message');
    expect(restored?.reference?.channelId, 'source-channel');
    expect(restored?.reference?.guildId, isNull);
    expect(
      restored?.reference?.type,
      DiscordMessageReferenceType.defaultReference,
    );
    expect(restored?.snapshots, isEmpty);
  });
}
