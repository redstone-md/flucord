import 'dart:io';

import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('a cached message keeps its components and @everyone flag', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);

    await cache.writeMessage(
      ChatMessage(
        id: 'message-1',
        channelId: 'channel-1',
        authorId: 'bot-1',
        body: 'Choose',
        sentAt: DateTime.utc(2026, 7, 24, 8),
        mentionsEveryone: true,
        componentRows: const [
          MessageActionRow(
            components: [
              MessageComponent(
                type: 2,
                customId: 'approve',
                label: 'Approve',
                style: MessageButtonStyle.success,
                isDisabled: true,
                emojiName: '🔥',
              ),
              MessageComponent(
                type: 2,
                customId: '',
                label: 'Docs',
                style: MessageButtonStyle.link,
                url: 'https://example.com/docs',
              ),
            ],
          ),
          MessageActionRow(
            components: [
              MessageComponent(
                type: 3,
                customId: 'pick',
                placeholder: 'Pick one',
                minValues: 0,
                maxValues: 2,
                options: [
                  MessageSelectOption(
                    value: 'a',
                    label: 'First',
                    description: 'The first one',
                    isDefault: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final restored = await cache.readMessage('message-1');

    expect(restored?.mentionsEveryone, isTrue);
    final [buttons, selects] = restored!.componentRows;
    final [approve, docs] = buttons.components;
    expect(approve.customId, 'approve');
    expect(approve.label, 'Approve');
    expect(approve.style, MessageButtonStyle.success);
    expect(approve.isDisabled, isTrue);
    expect(approve.emojiName, '🔥');
    expect(docs.isLink, isTrue);
    expect(docs.url, 'https://example.com/docs');
    final select = selects.components.single;
    expect(select.isSelect, isTrue);
    expect(select.placeholder, 'Pick one');
    expect(select.minValues, 0);
    expect(select.maxValues, 2);
    final option = select.options.single;
    expect(option.value, 'a');
    expect(option.label, 'First');
    expect(option.description, 'The first one');
    expect(option.isDefault, isTrue);
  });

  test('a message cached before v24 opens with neither', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-message-components-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 23,
        onCreate: (database, _) => database.execute(_v23Messages),
      ),
    );
    await legacy.insert('messages', {
      'id': 'v23-message',
      'channel_id': 'channel-1',
      'author_id': 'bot-1',
      'body': 'Before components',
      'message_type': 0,
      'reference_type': 0,
      'snapshots_json': '[]',
      'flags': 0,
      'sent_at': DateTime.utc(2026, 7, 23).toIso8601String(),
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
    final restored = await cache.readMessage('v23-message');

    expect(restored?.body, 'Before components');
    expect(restored?.componentRows, isEmpty);
    expect(restored?.mentionsEveryone, isFalse);
  });
}

const _v23Messages = '''
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
    is_text_to_speech INTEGER NOT NULL DEFAULT 0
  )
''';
