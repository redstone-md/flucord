import 'dart:io';

import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/scheduled_event_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';

const _guild = '100000000000000801';
const _event = '100000000000000802';
const _eventsPath = '/api/v9/guilds/$_guild/scheduled-events';

/// A user account's scheduled events: read through the cache, and kept
/// current by the gateway, the same way the bot transport keeps them.
void main() {
  setUpAll(sqfliteFfiInit);

  test('an RSVP echo moves the count the dialog shows', () async {
    final transport = FakeDiscordTransport()
      ..on('GET', _eventsPath, (_) => jsonResponse([_eventPayload(count: 3)]));
    final (repository, socket) = await _connect(transport);
    socket.receive(_ready());
    await (repository as ScheduledEventRepository).loadScheduledEvents(_guild);

    final upserted = repository.events.firstWhere(
      (event) => event is GuildScheduledEventUpsertedEvent,
    );
    socket.receive(
      _dispatch('GUILD_SCHEDULED_EVENT_USER_ADD', {
        'guild_id': _guild,
        'guild_scheduled_event_id': _event,
        'user_id': '100000000000000101',
      }),
    );

    expect(
      ((await upserted) as GuildScheduledEventUpsertedEvent)
          .event
          .interestedCount,
      4,
    );
  });

  test('events read once still show when Discord cannot be reached', () async {
    var online = true;
    final transport = FakeDiscordTransport()
      ..on(
        'GET',
        _eventsPath,
        (_) => online
            ? jsonResponse([_eventPayload(count: 3)])
            : throw const SocketException('offline'),
      );
    final (repository, _) = await _connect(transport);
    final events = repository as ScheduledEventRepository;
    await events.loadScheduledEvents(_guild);

    online = false;
    final offline = await events.loadScheduledEvents(_guild);

    expect(offline.single.id, _event);
  });
}

Map<String, Object?> _eventPayload({required int count}) => {
  'id': _event,
  'guild_id': _guild,
  'name': 'Forge night',
  'scheduled_start_time': '2026-08-01T18:00:00Z',
  'privacy_level': 2,
  'status': 1,
  'entity_type': 3,
  'entity_metadata': {'location': 'The workshop'},
  'user_count': count,
};

Future<(DiscordDesktopChatRepository, MemoryDesktopWebSocket)> _connect(
  FakeDiscordTransport transport,
) async {
  final socket = MemoryDesktopWebSocket.etf();
  final gateway = DiscordDesktopGatewayClient(
    authorization: 'account-session',
    properties: const {'os': 'Windows'},
    profile: const DiscordDesktopProtocolProfile(
      clientBuildNumber: 582977,
      gatewayEncoding: 'etf',
    ),
    socketConnector: MemoryDesktopWebSocketConnector.answering(socket),
  );
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  final repository = DiscordDesktopChatRepository(
    DiscordDesktopApiClient(
      authorization: 'account-session',
      headers: const {},
      transport: transport,
    ),
    gateway,
    cache,
  );
  addTearDown(repository.close);
  await gateway.connect('wss://gateway.discord.gg');
  return (repository, socket);
}

Map<String, Object?> _ready() => _dispatch('READY', {
  'session_id': 'session',
  'user': {'id': '100000000000000101'},
  'guilds': <Object?>[],
  'private_channels': <Object?>[],
}, 1);

Map<String, Object?> _dispatch(
  String name,
  Map<String, Object?> data, [
  int sequence = 2,
]) => {'op': 0, 's': sequence, 't': name, 'd': data};
