import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_message_nonce_factory.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('uses documented sticker list and Create Message payloads', () async {
    final transport = _QueueTransport([
      _response('[${_stickerJson('sticker-1', 'Signal', 2)}]'),
      _response(_messageJson),
    ]);
    final client = DiscordApiClient(botToken: 'token', transport: transport);

    final catalog = await client.getGuildStickers('guild-1');
    final sticker = DiscordMapper().guildSticker(catalog.single, 'guild-1');
    await client.createMessage(
      channelId: 'channel-1',
      content: '',
      stickerIds: const ['sticker-1'],
    );

    expect(transport.paths[0], '/api/v10/guilds/guild-1/stickers');
    expect(sticker.item.format.name, 'apng');
    expect(sticker.tags, ['signal', 'native']);
    expect(sticker.item.url, endsWith('/stickers/sticker-1.png'));
    final body = jsonDecode(utf8.decode(transport.bodies[1]!)) as Map;
    expect(body['sticker_ids'], ['sticker-1']);
  });

  test('repository enforces an idempotency nonce for sticker sends', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final fixedClock = DateTime.utc(2026, 7, 24, 3, 47);
    final expectedNonce =
        '${fixedClock.microsecondsSinceEpoch.toRadixString(36)}00';
    final transport = _QueueTransport([_response(_messageJson)]);
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      _FakeGateway(),
      cache,
      messageNonceFactory: DiscordMessageNonceFactory(clock: () => fixedClock),
    );
    addTearDown(repository.close);

    await repository.sendStickers(
      channelId: 'channel-1',
      authorId: 'bot-1',
      stickerIds: const ['sticker-1'],
    );

    final body = jsonDecode(utf8.decode(transport.bodies.single!)) as Map;
    expect(body['sticker_ids'], ['sticker-1']);
    expect(body['nonce'], expectedNonce);
    expect(body['enforce_nonce'], isTrue);
  });

  test('replaces and persists a guild sticker catalog from Gateway', () async {
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
      _response('[]'),
      _response('[${_stickerJson('sticker-old', 'Old signal', 1)}]'),
      _response('{"url":"wss://gateway.discord.gg"}'),
    ]);
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      gateway,
      cache,
    );
    addTearDown(repository.close);

    final workspace = await repository.loadWorkspace();
    expect(workspace.stickers.single.id, 'sticker-old');
    final emitted = repository.events
        .firstWhere((event) => event is GuildStickersReplacedEvent)
        .then((event) => event as GuildStickersReplacedEvent);

    gateway.emit(
      DiscordGatewayDispatch(
        name: 'GUILD_STICKERS_UPDATE',
        data: {
          'guild_id': 'guild-1',
          'stickers': [jsonDecode(_stickerJson('sticker-new', 'New relay', 3))],
        },
      ),
    );

    final event = await emitted.timeout(const Duration(seconds: 2));
    expect(event.stickers.single.item.format.name, 'lottie');
    final restored = await cache.readWorkspace();
    expect(restored?.stickers.single.id, 'sticker-new');
  });
}

String _stickerJson(String id, String name, int format) =>
    '{"id":"$id","name":"$name","description":"Native",'
    '"tags":"signal,native","format_type":$format,"available":true}';

const _messageJson =
    '{"id":"message-1","channel_id":"channel-1",'
    '"author":{"id":"bot-1"},"content":"",'
    '"timestamp":"2026-07-23T03:47:00Z","attachments":[],"embeds":[],'
    '"reactions":[],"sticker_items":['
    '{"id":"sticker-1","name":"Signal","format_type":2}]}';

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
  }) {}

  @override
  Future<void> close() => _events.close();
}

final class _QueueTransport implements DiscordHttpTransport {
  _QueueTransport(this._responses);

  final List<DiscordHttpResponse> _responses;
  final List<String> paths = [];
  final List<List<int>?> bodies = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    paths.add(uri.path);
    bodies.add(body);
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
