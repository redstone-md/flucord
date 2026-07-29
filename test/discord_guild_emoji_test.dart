import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('uses the documented guild emoji REST route and maps syntax', () async {
    final transport = _QueueTransport([
      const DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '[{"id":"emoji-1","name":"ship_it","animated":true,"available":true}]',
      ),
    ]);
    final client = DiscordApiClient(botToken: 'token', transport: transport);

    final payloads = await client.getGuildEmojis('guild-1');
    final emoji = DiscordMapper().emoji(payloads.single, 'guild-1');

    expect(transport.paths.single, '/api/v10/guilds/guild-1/emojis');
    expect(emoji.messageSyntax, '<a:ship_it:emoji-1>');
    expect(emoji.reactionKey, 'ship_it:emoji-1');
    expect(emoji.imageUrl, contains('/emojis/emoji-1.gif'));
  });

  test('replaces and persists a guild emoji catalog from Gateway', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final gateway = _FakeGateway();
    final transport = _QueueTransport([
      _response('{"id":"bot-1","username":"Flucord Bot"}'),
      _response('[{"id":"guild-1","name":"Forge","icon":null}]'),
      _response('[{"id":"channel-1","name":"general","type":0}]'),
      _response('{"threads":[]}'),
      _response('[]'),
      _response('[]'),
      _response('[{"id":"emoji-old","name":"old","animated":false}]'),
      _response('[]'),
      _response('{"url":"wss://gateway.discord.gg"}'),
    ]);
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      gateway,
      cache,
    );
    addTearDown(repository.close);

    final workspace = await repository.loadWorkspace();
    expect(workspace.emojis.single.id, 'emoji-old');
    final emitted = repository.events
        .firstWhere((event) => event is GuildEmojisReplacedEvent)
        .then((event) => event as GuildEmojisReplacedEvent);

    gateway.emit(
      DiscordGatewayDispatch(
        name: 'GUILD_EMOJIS_UPDATE',
        data: const {
          'guild_id': 'guild-1',
          'emojis': [
            {
              'id': 'emoji-new',
              'name': 'new_signal',
              'animated': true,
              'available': true,
            },
          ],
        },
      ),
    );

    final event = await emitted.timeout(const Duration(seconds: 2));
    expect(event.emojis.single.messageSyntax, '<a:new_signal:emoji-new>');
    final restored = await cache.readWorkspace();
    expect(restored?.emojis.single.id, 'emoji-new');
  });
}

DiscordHttpResponse _response(String body) =>
    DiscordHttpResponse(statusCode: 200, headers: const {}, body: body);

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
    bool selfVideo = false,
  }) {}

  @override
  void pingVoiceServer() {}

  @override
  Future<void> close() => _events.close();
}

final class _QueueTransport implements DiscordHttpTransport {
  _QueueTransport(this._responses);

  final List<DiscordHttpResponse> _responses;
  final List<String> paths = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    paths.add(uri.path);
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
