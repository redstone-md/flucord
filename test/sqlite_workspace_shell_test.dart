import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'the workspace shell carries navigation without message history',
    () async {
      final cache = await _openCache();
      await cache.writeWorkspace(_workspace);
      await cache.writeChannelHistory(
        ChannelHistory(
          channelId: 'channel-1',
          messages: List.generate(40, _message),
          members: const [_member],
        ),
      );

      final shell = await cache.readWorkspaceShell();

      expect(shell, isNotNull);
      expect(shell!.currentMemberId, 'member-1');
      expect(shell.spaces.map((space) => space.id), ['guild-1']);
      expect(shell.channels.map((channel) => channel.id), ['channel-1']);
      expect(shell.categories.map((category) => category.id), ['category-1']);
      expect(shell.roles.map((role) => role.id), ['role-1']);
      expect(shell.messages, isEmpty);
      expect(shell.members, isEmpty);
    },
  );

  test(
    'the workspace shell keeps the channel activity a restore reads',
    () async {
      final cache = await _openCache();
      await cache.writeWorkspace(_workspace);

      final shell = await cache.readWorkspaceShell();
      final channel = shell!.channelById('channel-1');

      expect(channel.unread, isTrue);
      expect(channel.mentionCount, 2);
      expect(channel.firstUnreadMessageId, 'message-4');
    },
  );

  test('an empty cache has no workspace shell', () async {
    final cache = await _openCache();

    expect(await cache.readWorkspaceShell(), isNull);
  });
}

Future<SqliteChatCache> _openCache() async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  addTearDown(cache.close);
  return cache;
}

const _member = Member(
  id: 'member-1',
  displayName: 'Jack',
  initials: 'JK',
  role: 'Operator',
  presence: Presence.online,
  colorValue: 0xff456b5a,
);

ChatMessage _message(int index) => ChatMessage(
  id: 'message-$index',
  channelId: 'channel-1',
  authorId: 'member-1',
  body: 'Message $index',
  sentAt: DateTime.utc(2024, 1, 1).add(Duration(minutes: index)),
);

final _workspace = ChatWorkspace(
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
      position: 2,
      parentId: 'category-1',
      unread: true,
      mentionCount: 2,
      firstUnreadMessageId: 'message-4',
    ),
  ],
  categories: const [
    ChannelCategory(
      id: 'category-1',
      spaceId: 'guild-1',
      name: 'Work',
      position: 0,
    ),
  ],
  roles: const [
    CommunityRole(
      id: 'role-1',
      spaceId: 'guild-1',
      name: 'Operator',
      position: 1,
    ),
  ],
  members: const [_member],
  messages: const [],
  currentMemberId: 'member-1',
);
