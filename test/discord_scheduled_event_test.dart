import 'dart:async';
import 'dart:convert';

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

  test('lists and maps documented guild scheduled events', () async {
    final transport = _QueueTransport([
      _response('[${_eventJson(status: 1, count: 12)}]'),
    ]);
    final client = DiscordApiClient(botToken: 'token', transport: transport);

    final payloads = await client.getGuildScheduledEvents('guild-1');
    final event = DiscordMapper().guildScheduledEvent(payloads.single)!;

    expect(
      transport.uris.single.path,
      '/api/v10/guilds/guild-1/scheduled-events',
    );
    expect(transport.uris.single.queryParameters['with_user_count'], 'true');
    expect(event.location, 'Build room');
    expect(event.entityType.name, 'external');
    expect(event.status.name, 'scheduled');
    expect(event.interestedCount, 12);
  });

  test('persists scheduled event and subscriber Gateway updates', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final gateway = _FakeGateway();
    final transport = _QueueTransport([
      _response('{"id":"bot-1","username":"Flucord Bot"}'),
      _response('[{"id":"guild-1","name":"Forge","icon":null}]'),
      _response('[{"id":"channel-1","name":"stage","type":2}]'),
      _response('{"threads":[]}'),
      _response('[]'),
      _response('[]'),
      _response('[]'),
      _response('[]'),
      _response('{"url":"wss://gateway.discord.gg"}'),
      _response('[${_eventJson(status: 1, count: 4)}]'),
    ]);
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      gateway,
      cache,
    );
    addTearDown(repository.close);

    await repository.loadWorkspace();
    final initial = await repository.loadScheduledEvents('guild-1');
    expect(initial.single.interestedCount, 4);

    final updated = repository.events
        .firstWhere((event) => event is GuildScheduledEventUpsertedEvent)
        .then((event) => event as GuildScheduledEventUpsertedEvent);
    gateway.emit(
      DiscordGatewayDispatch(
        name: 'GUILD_SCHEDULED_EVENT_UPDATE',
        data: (jsonDecode(_eventJson(status: 2, count: 7)) as Map)
            .cast<String, Object?>(),
      ),
    );
    expect((await updated).event.isActive, isTrue);

    final subscribed = repository.events
        .firstWhere((event) => event is GuildScheduledEventUpsertedEvent)
        .then((event) => event as GuildScheduledEventUpsertedEvent);
    gateway.emit(
      const DiscordGatewayDispatch(
        name: 'GUILD_SCHEDULED_EVENT_USER_ADD',
        data: {
          'guild_id': 'guild-1',
          'guild_scheduled_event_id': 'event-1',
          'user_id': 'user-1',
        },
      ),
    );
    expect((await subscribed).event.interestedCount, 8);
    expect(
      (await cache.readGuildScheduledEvents('guild-1')).single.interestedCount,
      8,
    );

    final deleted = repository.events
        .firstWhere((event) => event is GuildScheduledEventDeletedEvent)
        .then((event) => event as GuildScheduledEventDeletedEvent);
    gateway.emit(
      DiscordGatewayDispatch(
        name: 'GUILD_SCHEDULED_EVENT_DELETE',
        data: (jsonDecode(_eventJson(status: 4, count: 8)) as Map)
            .cast<String, Object?>(),
      ),
    );
    expect((await deleted).eventId, 'event-1');
    expect(await cache.readGuildScheduledEvents('guild-1'), isEmpty);
  });
}

String _eventJson({required int status, required int count}) =>
    '{"id":"event-1","guild_id":"guild-1","channel_id":null,'
    '"name":"Release checkpoint","description":"Final review",'
    '"scheduled_start_time":"2026-07-24T18:00:00Z",'
    '"scheduled_end_time":"2026-07-24T19:00:00Z",'
    '"privacy_level":2,"status":$status,"entity_type":3,'
    '"entity_metadata":{"location":"Build room"},"user_count":$count}';

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
  void pingVoiceServer() {}

  @override
  Future<void> close() => _events.close();
}

final class _QueueTransport implements DiscordHttpTransport {
  _QueueTransport(this._responses);

  final List<DiscordHttpResponse> _responses;
  final List<Uri> uris = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    uris.add(uri);
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
