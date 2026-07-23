import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
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
      ],
      members: const [
        Member(
          id: 'user-1',
          displayName: 'Jack',
          initials: 'JK',
          role: 'Bot',
          presence: Presence.online,
          colorValue: 0xff48745f,
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
    expect(restored?.channels.single.name, 'general');
    expect(restored?.currentMemberId, 'user-1');
    expect(history.messages.single.body, 'SQLite path confirmed.');
    expect(history.members.single.displayName, 'Jack');

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
    expect(updated.messages.single.body, 'SQLite upsert confirmed.');
    expect(updated.messages.single.isEdited, isTrue);
  });
}
