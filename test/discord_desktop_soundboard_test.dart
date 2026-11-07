import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';

const _home = '100000000000000501';
const _other = '100000000000000502';
const _joined = '100000000000000503';
const _voice = '100000000000000601';
const _dm = '100000000000000602';

/// The soundboard of every server the account is in, as the desktop client
/// asks the gateway for it: opcode 31 out, `SOUNDBOARD_SOUNDS` back.
void main() {
  setUpAll(sqfliteFfiInit);

  test('READY asks for every server\'s sounds in one request', () async {
    final (_, socket) = await _connect();

    socket.receive(_ready([_home, _other]));
    await _waitFor(() => _soundRequests(socket).isNotEmpty);

    expect(_soundRequests(socket), [
      {
        'guild_ids': [_home, _other],
      },
    ]);
  });

  test('the answer fills the catalogue, server by server', () async {
    final (repository, socket) = await _connect();
    final soundboard = repository.soundboard!;

    socket
      ..receive(_ready([_home, _other]))
      ..receive(
        _dispatch('SOUNDBOARD_SOUNDS', {
          'guild_id': _other,
          'soundboard_sounds': [
            {'sound_id': '100000000000000701', 'name': 'airhorn'},
          ],
        }),
      );
    await _waitFor(() => soundboard.catalogue.byGuild.isNotEmpty);

    final sound = soundboard.catalogue.find('100000000000000701')!;
    expect(sound.name, 'airhorn');
    // The answer names the server, and the sound keeps it as its source.
    expect(sound.guildId, _other);
  });

  test('a server joined later is asked for alone, and only once', () async {
    final (_, socket) = await _connect();
    socket.receive(_ready([_home]));
    await _waitFor(() => _soundRequests(socket).length == 1);

    socket
      ..receive(_dispatch('GUILD_CREATE', {'id': _joined, 'channels': []}, 3))
      ..receive(_dispatch('GUILD_CREATE', {'id': _joined, 'channels': []}, 4))
      ..receive(_dispatch('GUILD_CREATE', {'id': _home, 'channels': []}, 5));
    await _waitFor(() => _soundRequests(socket).length == 2);
    // Room for a third request to show up, had one been sent.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(_soundRequests(socket).last, {
      'guild_ids': [_joined],
    });
    expect(_soundRequests(socket), hasLength(2));
  });

  test('a server back from an outage is asked for again', () async {
    final (_, socket) = await _connect();
    socket.receive(_ready([_home]));
    await _waitFor(() => _soundRequests(socket).length == 1);

    socket
      ..receive(
        _dispatch('GUILD_DELETE', {'id': _home, 'unavailable': true}, 3),
      )
      ..receive(_dispatch('GUILD_CREATE', {'id': _home, 'channels': []}, 4));
    await _waitFor(() => _soundRequests(socket).length == 2);

    expect(_soundRequests(socket).last, {
      'guild_ids': [_home],
    });
  });

  test('a server the account left loses its sounds', () async {
    final (repository, socket) = await _connect();
    final soundboard = repository.soundboard!;
    socket
      ..receive(_ready([_home]))
      ..receive(
        _dispatch('SOUNDBOARD_SOUNDS', {
          'guild_id': _home,
          'soundboard_sounds': [
            {'sound_id': '100000000000000701', 'name': 'airhorn'},
          ],
        }),
      );
    await _waitFor(() => soundboard.catalogue.byGuild.isNotEmpty);

    // An outage is not a departure: the sounds come back with the server.
    socket.receive(
      _dispatch('GUILD_DELETE', {'id': _home, 'unavailable': true}, 3),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(soundboard.catalogue.byGuild, isNotEmpty);

    socket.receive(_dispatch('GUILD_DELETE', {'id': _home}, 4));
    await _waitFor(() => soundboard.catalogue.byGuild.isEmpty);
  });

  group('playing', () {
    test('another server\'s sound names its source server', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'POST',
          '/api/v9/channels/$_voice/send-soundboard-sound',
          (_) => jsonResponse(null, statusCode: 204),
        );
      final repository = await _repository(transport);

      await repository.soundboard!.playSound(
        _voice,
        const SoundboardSound(
          id: '100000000000000701',
          name: 'airhorn',
          guildId: _other,
        ),
      );

      final request = transport.requests.last;
      expect(request.method, 'POST');
      expect(request.json, {
        'sound_id': '100000000000000701',
        'source_guild_id': _other,
      });
    });

    test('a DM call takes the same route, on the DM channel', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'POST',
          '/api/v9/channels/$_dm/send-soundboard-sound',
          (_) => jsonResponse(null, statusCode: 204),
        );
      final repository = await _repository(transport);

      await repository.soundboard!.playSound(
        _dm,
        const SoundboardSound(id: '3', name: 'quack'),
      );

      final request = transport.requests.last;
      expect(request.uri.path, '/api/v9/channels/$_dm/send-soundboard-sound');
      // A default sound belongs to no server, so no source goes with it.
      expect(request.json, {'sound_id': '3'});
    });
  });
}

Future<(DiscordDesktopChatRepository, MemoryDesktopWebSocket)>
_connect() async {
  final socket = MemoryDesktopWebSocket.etf();
  final gateway = DiscordDesktopGatewayClient(
    authorization: 'account-session',
    properties: const {'os': 'Windows'},
    profile: _uncompressed,
    socketConnector: MemoryDesktopWebSocketConnector.answering(socket),
  );
  final repository = await _repository(FakeDiscordTransport(), gateway);
  await gateway.connect('wss://gateway.discord.gg');
  return (repository, socket);
}

Future<DiscordDesktopChatRepository> _repository(
  FakeDiscordTransport transport, [
  DiscordDesktopGatewayClient? gateway,
]) async {
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
    gateway ??
        DiscordDesktopGatewayClient(
          authorization: 'account-session',
          properties: const {'os': 'Windows'},
          socketConnector: MemoryDesktopWebSocketConnector(),
        ),
    cache,
  );
  addTearDown(repository.close);
  return repository;
}

Map<String, Object?> _ready(List<String> guildIds) => _dispatch('READY', {
  'session_id': 'session',
  'user': {'id': '100000000000000101'},
  'guilds': [
    for (final id in guildIds)
      {
        'id': id,
        'roles': [
          {'id': id, 'name': '@everyone', 'permissions': '1024'},
        ],
        'channels': <Object?>[],
      },
  ],
  'private_channels': <Object?>[],
}, 1);

Map<String, Object?> _dispatch(
  String name,
  Map<String, Object?> data, [
  int sequence = 2,
]) => {'op': 0, 's': sequence, 't': name, 'd': data};

/// The `d` of every opcode 31 frame the client sent, oldest first.
List<Object?> _soundRequests(MemoryDesktopWebSocket socket) => [
  for (final frame in socket.frames)
    if (frame['op'] == 31) frame['d'],
];

const _uncompressed = DiscordDesktopProtocolProfile(
  clientBuildNumber: 582977,
  gatewayEncoding: 'etf',
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}
