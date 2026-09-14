import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_history_loader.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('serves cached history in cursor pages while offline', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    await cache.writeChannelHistory(
      ChannelHistory(
        channelId: 'channel-1',
        messages: List.generate(205, _message),
        members: const [_member],
      ),
    );
    final loader = DiscordHistoryLoader(
      DiscordApiClient(botToken: 'token', transport: _OfflineTransport()),
      DiscordMapper(),
      cache,
    );

    final latest = await loader.load('channel-1');
    final middle = await loader.load(
      'channel-1',
      beforeMessageId: latest.history.messages.first.id,
    );
    final oldest = await loader.load(
      'channel-1',
      beforeMessageId: middle.history.messages.first.id,
    );

    expect(latest.history.messages, hasLength(100));
    expect(latest.history.messages.first.id, 'm105');
    expect(latest.hasMore, isTrue);
    expect(middle.history.messages, hasLength(100));
    expect(middle.history.messages.first.id, 'm005');
    expect(middle.hasMore, isTrue);
    expect(oldest.history.messages.map((item) => item.id), [
      'm000',
      'm001',
      'm002',
      'm003',
      'm004',
    ]);
    expect(oldest.hasMore, isFalse);
  });
}

ChatMessage _message(int index) => ChatMessage(
  id: 'm${index.toString().padLeft(3, '0')}',
  channelId: 'channel-1',
  authorId: 'bot-1',
  body: 'Cached message $index',
  sentAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
);

const _member = Member(
  id: 'bot-1',
  displayName: 'Flucord',
  initials: 'FL',
  role: 'Bot',
  presence: Presence.online,
  colorValue: 0xff456b5a,
);

final class _OfflineTransport implements DiscordHttpTransport {
  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async => const DiscordHttpResponse(
    statusCode: 503,
    headers: {},
    body: '{"message":"offline"}',
  );

  @override
  void close() {}
}
