import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/message_embed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('persists workspace, channel history, and message upserts', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);

    final workspace = ChatWorkspace(
      spaces: const [
        CommunitySpace(
          id: 'guild-1',
          name: 'Forge',
          monogram: 'FO',
          colorValue: 0xff456b5a,
          iconUrl: 'https://cdn.discordapp.com/icons/guild-1/icon.webp',
        ),
      ],
      channels: const [
        ConversationChannel(
          id: 'channel-1',
          spaceId: 'guild-1',
          name: 'general',
          topic: 'Core work',
          kind: ChannelKind.text,
        ),
        ConversationChannel(
          id: 'thread-1',
          spaceId: 'guild-1',
          name: 'release-thread',
          topic: '',
          kind: ChannelKind.text,
          parentId: 'channel-1',
          isThread: true,
        ),
      ],
      members: const [
        Member(
          id: 'user-1',
          displayName: 'Jack',
          initials: 'JK',
          role: 'Bot',
          presence: Presence.online,
          colorValue: 0xff48745f,
          spaceIds: {'guild-1'},
          rolesBySpace: {'guild-1': 'Bot'},
          avatarUrl: 'https://cdn.discordapp.com/avatars/user-1/global.webp',
          avatarUrlsBySpace: {
            'guild-1':
                'https://cdn.discordapp.com/guilds/guild-1/users/user-1/avatars/member.webp',
          },
        ),
      ],
      messages: const [],
      currentMemberId: 'user-1',
    );
    final message = ChatMessage(
      id: 'message-1',
      channelId: 'channel-1',
      authorId: 'user-1',
      body: 'SQLite path confirmed.',
      sentAt: DateTime.utc(2026, 7, 23, 2, 30),
      attachments: const [
        MessageAttachment(
          id: 'attachment-1',
          fileName: 'proof.png',
          url: 'https://cdn.discordapp.com/proof.png',
          size: 2048,
          contentType: 'image/png',
          width: 800,
          height: 600,
        ),
      ],
      reply: const MessageReply(
        messageId: 'message-0',
        authorId: 'user-1',
        body: 'Original message',
      ),
      reactions: const [
        MessageReaction(
          emojiName: 'check',
          emojiId: '42',
          count: 3,
          reactedByCurrentUser: true,
        ),
      ],
      embeds: [
        MessageEmbed(
          type: 'rich',
          title: 'Build report',
          description: 'All native checks passed.',
          colorValue: 0x4c9b72,
          fields: const [
            MessageEmbedField(name: 'Tests', value: '91', isInline: true),
          ],
        ),
      ],
      isPinned: true,
    );

    await cache.writeWorkspace(workspace);
    await cache.writeChannelHistory(
      ChannelHistory(
        channelId: 'channel-1',
        messages: [message],
        members: workspace.members,
      ),
    );

    final restored = await cache.readWorkspace();
    final history = await cache.readChannelHistory('channel-1');

    expect(restored?.spaces.single.name, 'Forge');
    expect(restored?.spaces.single.iconUrl, contains('/icons/guild-1/'));
    expect(restored?.channels.first.name, 'general');
    expect(restored?.channels.last.isThread, isTrue);
    expect(restored?.channels.last.parentId, 'channel-1');
    expect(restored?.currentMemberId, 'user-1');
    expect(history.messages.single.body, 'SQLite path confirmed.');
    expect(history.messages.single.attachments.single.fileName, 'proof.png');
    expect(history.messages.single.reply?.messageId, 'message-0');
    expect(history.messages.single.reactions.single.count, 3);
    expect(history.messages.single.embeds.single.title, 'Build report');
    expect(history.messages.single.embeds.single.fields.single.value, '91');
    expect(history.members.single.displayName, 'Jack');
    expect(history.members.single.roleFor('guild-1'), 'Bot');
    expect(history.members.single.avatarUrl, contains('/avatars/user-1/'));
    expect(
      history.members.single.avatarUrlFor('guild-1'),
      contains('/guilds/guild-1/users/user-1/'),
    );
    expect(history.messages.single.isPinned, isTrue);
    expect(
      (await cache.readPinnedMessages('channel-1')).messages.single.id,
      'message-1',
    );

    final edited = ChatMessage(
      id: message.id,
      channelId: message.channelId,
      authorId: message.authorId,
      body: 'SQLite upsert confirmed.',
      sentAt: message.sentAt,
      isEdited: true,
    );
    await cache.writeMessage(edited);

    final updated = await cache.readChannelHistory('channel-1');
    final direct = await cache.readMessage('message-1');
    expect(updated.messages.single.body, 'SQLite upsert confirmed.');
    expect(updated.messages.single.isEdited, isTrue);
    expect(direct?.body, 'SQLite upsert confirmed.');
  });

  test('appends paginated history without deleting newer messages', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    ChatMessage message(String id, int minute) => ChatMessage(
      id: id,
      channelId: 'channel-1',
      authorId: 'user-1',
      body: id,
      sentAt: DateTime.utc(2026, 7, 23, 2, minute),
    );
    const member = Member(
      id: 'user-1',
      displayName: 'Jack',
      initials: 'JK',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff48745f,
    );

    await cache.writeChannelHistory(
      ChannelHistory(
        channelId: 'channel-1',
        messages: [message('newer', 2)],
        members: const [member],
      ),
    );
    await cache.writeChannelHistory(
      ChannelHistory(
        channelId: 'channel-1',
        messages: [message('older', 1)],
        members: const [member],
      ),
      replaceExisting: false,
    );

    final restored = await cache.readChannelHistory('channel-1');
    expect(restored.messages.map((item) => item.id), ['older', 'newer']);
  });

  test('migrates the version 1 message and channel schema', () async {
    final directory = await Directory.systemTemp.createTemp('flucord-db-test-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}legacy.sqlite3';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE spaces (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              monogram TEXT NOT NULL,
              color_value INTEGER NOT NULL,
              sort_index INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE channels (
              id TEXT PRIMARY KEY,
              space_id TEXT NOT NULL,
              name TEXT NOT NULL,
              topic TEXT NOT NULL,
              kind INTEGER NOT NULL,
              unread INTEGER NOT NULL,
              mention_count INTEGER NOT NULL,
              sort_index INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE members (
              id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL,
              initials TEXT NOT NULL,
              role TEXT NOT NULL,
              presence INTEGER NOT NULL,
              color_value INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE messages (
              id TEXT PRIMARY KEY,
              channel_id TEXT NOT NULL,
              author_id TEXT NOT NULL,
              body TEXT NOT NULL,
              sent_at TEXT NOT NULL,
              is_edited INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await legacy.close();

    final migrated = await SqliteChatCache.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    await migrated.close();
    final database = await databaseFactoryFfi.openDatabase(path);
    addTearDown(database.close);
    final channelColumns = await database.rawQuery(
      'PRAGMA table_info(channels)',
    );
    final messageColumns = await database.rawQuery(
      'PRAGMA table_info(messages)',
    );
    final memberColumns = await database.rawQuery('PRAGMA table_info(members)');
    final spaceColumns = await database.rawQuery('PRAGMA table_info(spaces)');

    expect(channelColumns.map((row) => row['name']), contains('is_thread'));
    expect(
      messageColumns.map((row) => row['name']),
      contains('attachments_json'),
    );
    expect(
      messageColumns.map((row) => row['name']),
      contains('reactions_json'),
    );
    expect(messageColumns.map((row) => row['name']), contains('is_pinned'));
    expect(
      memberColumns.map((row) => row['name']),
      contains('roles_by_space_json'),
    );
    expect(memberColumns.map((row) => row['name']), contains('avatar_url'));
    expect(
      memberColumns.map((row) => row['name']),
      contains('avatar_urls_by_space_json'),
    );
    expect(spaceColumns.map((row) => row['name']), contains('icon_url'));
    expect(messageColumns.map((row) => row['name']), contains('embeds_json'));
  });
}
