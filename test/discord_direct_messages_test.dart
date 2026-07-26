import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('discovers, emits, and caches an incoming bot direct message', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final gateway = _FakeGateway();
    final transport = _QueueTransport([
      const DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body: '{"id":"bot-1","username":"Flucord Bot"}',
      ),
      const DiscordHttpResponse(statusCode: 200, headers: {}, body: '[]'),
      const DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body: '{"url":"wss://gateway.discord.gg"}',
      ),
      const DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body: '{"id":"bot-1","username":"Flucord Bot"}',
      ),
      const DiscordHttpResponse(statusCode: 200, headers: {}, body: '[]'),
      const DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body: '{"url":"wss://gateway.discord.gg"}',
      ),
    ]);
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      gateway,
      cache,
    );
    addTearDown(repository.close);

    final workspace = await repository.loadWorkspace();
    expect(workspace.spaces.single.kind, SpaceKind.directMessages);
    expect(workspace.channels, isEmpty);
    final emitted = repository.events.take(4).toList();

    gateway.emit(
      DiscordGatewayDispatch(
        name: 'MESSAGE_CREATE',
        data: {
          'id': 'message-1',
          'channel_id': 'dm-1',
          'channel_type': 1,
          'content': 'Native DM path',
          'timestamp': '2026-07-23T10:30:00Z',
          'edited_timestamp': null,
          'attachments': <Object?>[],
          'embeds': <Object?>[],
          'reactions': <Object?>[],
          'mentions': <Object?>[],
          'author': {
            'id': '123456789012345678',
            'username': 'jack',
            'global_name': 'Jack',
            'avatar': 'avatar-hash',
          },
        },
      ),
    );

    final events = await emitted.timeout(const Duration(seconds: 2));
    expect(events[0], isA<SpaceUpsertedEvent>());
    expect(events[1], isA<MemberUpsertedEvent>());
    expect(events[2], isA<ChannelUpsertedEvent>());
    expect(events[3], isA<MessageUpsertedEvent>());
    final restored = await cache.readWorkspace();
    expect(restored?.channels.single.recipientId, '123456789012345678');
    expect(restored?.messages.single.body, 'Native DM path');
    expect(restored?.memberById('123456789012345678').displayName, 'Jack');

    final reloaded = await repository.loadWorkspace();
    expect(reloaded.channels.single.id, 'dm-1');
    expect(reloaded.messages.single.body, 'Native DM path');
  });
}

final class _FakeGateway implements DiscordChatGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();

  void emit(DiscordGatewayEvent event) => _events.add(event);

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  @override
  Future<void> connect(String gatewayUrl) async {}

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
  }) {}

  @override
  void pingVoiceServer() {}

  @override
  Future<void> close() => _events.close();
}

final class _QueueTransport implements DiscordHttpTransport {
  _QueueTransport(this._responses);

  final List<DiscordHttpResponse> _responses;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async => _responses.removeAt(0);

  @override
  void close() {}
}
