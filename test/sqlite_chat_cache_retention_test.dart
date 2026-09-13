import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<SqliteChatCache> openCache() async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    await cache.writeWorkspace(_workspace());
    return cache;
  }

  ChatMessage message(String id, String channelId, int minutes) => ChatMessage(
    id: id,
    channelId: channelId,
    authorId: 'user-1',
    body: 'message $id',
    sentAt: DateTime.utc(2026, 7, 23).add(Duration(minutes: minutes)),
  );

  // Channel minutes are offset apart so no two messages tie on sent_at.
  ChatMessage messageIn(String channelId, int index) => message(
    'm-$channelId-$index',
    channelId,
    channelId == 'channel-1' ? index : 1000 + index,
  );

  ChannelHistory historyOf(String channelId, List<ChatMessage> messages) =>
      ChannelHistory(channelId: channelId, messages: messages, members: const []);

  test('history writes beyond the cap prune the oldest of the channel', () async {
    final cache = await openCache();
    final count = SqliteChatCache.historyPerChannel + 20;
    await cache.writeChannelHistory(
      historyOf(
        'channel-1',
        List.generate(count, (index) => message('m-$index', 'channel-1', index)),
      ),
    );

    final history = await cache.readChannelHistory('channel-1');
    expect(history.messages, hasLength(SqliteChatCache.historyPerChannel));
    // The tail survives, the head does not.
    expect(history.messages.first.id, 'm-20');
    expect(history.messages.last.id, 'm-${count - 1}');
  });

  test('single message writes prune the channel too', () async {
    final cache = await openCache();
    for (var index = 0; index < 5; index++) {
      await cache.writeMessage(
        message('m-$index', 'channel-1', index),
      );
    }
    final before = await cache.readChannelHistory('channel-1');
    expect(before.messages, hasLength(5));

    final overflow = SqliteChatCache.historyPerChannel + 5;
    for (var index = 5; index < overflow; index++) {
      await cache.writeMessage(message('m-$index', 'channel-1', index));
    }

    final after = await cache.readChannelHistory('channel-1');
    expect(after.messages, hasLength(SqliteChatCache.historyPerChannel));
    expect(after.messages.first.id, 'm-5');
  });

  test('the cap is per channel, not shared', () async {
    final cache = await openCache();
    for (final channelId in ['channel-1', 'channel-2']) {
      await cache.writeChannelHistory(
        historyOf(
          channelId,
          List.generate(
            SqliteChatCache.historyPerChannel + 1,
            (index) => message('m-$channelId-$index', channelId, index),
          ),
        ),
      );
    }

    for (final channelId in ['channel-1', 'channel-2']) {
      final history = await cache.readChannelHistory(channelId);
      expect(history.messages, hasLength(SqliteChatCache.historyPerChannel));
      expect(
        history.messages.first.id,
        'm-$channelId-1',
        reason: 'each channel keeps its own newest page',
      );
    }
  });

  test('the offline workspace read is bounded per channel', () async {
    final cache = await openCache();
    for (final channelId in ['channel-1', 'channel-2']) {
      await cache.writeChannelHistory(
        historyOf(
          channelId,
          List.generate(
            SqliteChatCache.historyPerChannel,
            (index) => messageIn(channelId, index),
          ),
        ),
      );
    }

    final workspace = await cache.readWorkspace();
    expect(
      workspace!.messages,
      hasLength(SqliteChatCache.offlineHistoryPerChannel * 2),
    );
    // Still one row per message, ordered oldest first as before: each
    // channel contributes its newest page only.
    final oldestKept =
        SqliteChatCache.historyPerChannel -
        SqliteChatCache.offlineHistoryPerChannel;
    expect(workspace.messages.first.id, 'm-channel-1-$oldestKept');
    expect(
      workspace.messages.last.id,
      'm-channel-2-${SqliteChatCache.historyPerChannel - 1}',
    );
  });
}

ChatWorkspace _workspace() => ChatWorkspace(
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
      topic: '',
      kind: ChannelKind.text,
      position: 0,
    ),
    ConversationChannel(
      id: 'channel-2',
      spaceId: 'guild-1',
      name: 'archive',
      topic: '',
      kind: ChannelKind.text,
      position: 1,
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
