import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/chat_model_json.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_reaction_handler.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('loads reaction users with encoded emoji, type, and cursor', () async {
    final transport = _RecordingTransport(
      const DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '[{"id":"200","username":"jack","global_name":"Jack",'
            '"avatar":null}]',
      ),
    );
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      _FakeGateway(),
      cache,
    );
    addTearDown(repository.close);

    final page = await repository.loadReactionUsers(
      channelId: 'channel-1',
      messageId: 'message-1',
      emoji: 'forge spark:123',
      type: DiscordReactionType.burst,
      afterUserId: '100',
      limit: 25,
    );

    expect(
      transport.uri.toString(),
      contains('/reactions/forge%20spark%3A123'),
    );
    expect(transport.uri.queryParameters['type'], '1');
    expect(transport.uri.queryParameters['after'], '100');
    expect(transport.uri.queryParameters['limit'], '25');
    expect(page.users.single.displayName, 'Jack');
    expect(page.hasMore, isFalse);
  });

  test('maps and persists normal and burst reaction metadata', () {
    final message = DiscordMapper().message({
      'id': 'message-1',
      'channel_id': 'channel-1',
      'author': {'id': 'author-1'},
      'content': 'Ship it',
      'timestamp': '2026-07-24T08:00:00Z',
      'reactions': [
        {
          'count': 5,
          'count_details': {'normal': 3, 'burst': 2},
          'me': true,
          'me_burst': false,
          'emoji': {'id': null, 'name': '🔥'},
          'burst_colors': ['#ff3366'],
        },
      ],
    });
    final reaction = message.reactions.single;

    expect(reaction.normalCount, 3);
    expect(reaction.burstCount, 2);
    expect(reaction.burstColorValues, [0xffff3366]);

    final restored = ChatModelJson.reactionsFrom(
      ChatModelJson.reactions(message.reactions),
    ).single;
    expect(restored.normalCount, 3);
    expect(restored.burstCount, 2);
    expect(restored.burstColorValues, [0xffff3366]);
  });

  test(
    'applies burst Gateway events without corrupting normal counts',
    () async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(cache.close);
      await cache.writeMessage(
        ChatMessage(
          id: 'message-1',
          channelId: 'channel-1',
          authorId: 'author-1',
          body: 'Ship it',
          sentAt: DateTime(2026, 7, 24, 8),
          reactions: const [MessageReaction(emojiName: '🔥', count: 1)],
        ),
      );
      final handler = DiscordReactionHandler(cache, () => 'user-1');

      final added = await handler.apply(
        const DiscordGatewayDispatch(
          name: 'MESSAGE_REACTION_ADD',
          data: {
            'message_id': 'message-1',
            'user_id': 'user-1',
            'type': 1,
            'emoji': {'id': null, 'name': '🔥'},
            'burst_colors': ['#ff3366'],
          },
        ),
      );
      final afterAdd = added!.message.reactions.single;
      expect(afterAdd.count, 2);
      expect(afterAdd.normalCount, 1);
      expect(afterAdd.burstCount, 1);
      expect(afterAdd.burstByCurrentUser, isTrue);
      expect(afterAdd.burstColorValues, [0xffff3366]);

      final removed = await handler.apply(
        const DiscordGatewayDispatch(
          name: 'MESSAGE_REACTION_REMOVE',
          data: {
            'message_id': 'message-1',
            'user_id': 'user-1',
            'type': 1,
            'emoji': {'id': null, 'name': '🔥'},
          },
        ),
      );
      final afterRemove = removed!.message.reactions.single;
      expect(afterRemove.count, 1);
      expect(afterRemove.normalCount, 1);
      expect(afterRemove.burstCount, 0);
      expect(afterRemove.burstByCurrentUser, isFalse);
      expect(afterRemove.burstColorValues, isEmpty);
    },
  );
}

final class _RecordingTransport implements DiscordHttpTransport {
  _RecordingTransport(this.response);

  final DiscordHttpResponse response;
  late Uri uri;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    this.uri = uri;
    return response;
  }

  @override
  void close() {}
}

final class _FakeGateway implements DiscordChatGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  @override
  String? get sessionId => 'session-1';

  @override
  Future<void> connect(String gatewayUrl) async {}

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) {}

  @override
  void pingVoiceServer() {}

  @override
  Future<void> close() => _events.close();
}
