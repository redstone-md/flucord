import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_etf_codec.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _me = '111111111111111111';
const _mira = '222222222222222222';
const _roman = '333333333333333333';

/// The installed profile negotiates zstd-stream; these tests drive the socket
/// with plain ETF terms, so they pin the encoding without transport
/// compression.
const _uncompressed = DiscordDesktopProtocolProfile(clientBuildNumber: 582977);

void main() {
  setUpAll(sqfliteFfiInit);

  Future<(DiscordDesktopChatRepository, _MemorySocket)> connect() async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final socket = _MemorySocket();
    final gateway = DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      profile: _uncompressed,
      socketConnector: _MemorySocketConnector(socket),
    );
    final repository = DiscordDesktopChatRepository(
      DiscordDesktopApiClient(
        authorization: 'account-session',
        headers: const {},
        transport: _UnusedTransport(),
      ),
      gateway,
      cache,
    );
    addTearDown(repository.close);
    await gateway.connect('wss://gateway.discord.gg');
    return (repository, socket);
  }

  const ready = {
    'op': 0,
    's': 1,
    't': 'READY',
    'd': {
      'session_id': 'session',
      'user': {'id': _me},
      'guilds': <Object?>[],
      'private_channels': <Object?>[],
      'sessions': [
        {
          'session_id': 'session',
          'status': 'online',
          'active': true,
          'client_info': {'os': 'windows'},
        },
      ],
    },
  };

  test('a presence dispatch reaches the repository as a batch', () async {
    final (repository, socket) = await connect();
    final events = <ChatRepositoryEvent>[];
    repository.events.listen(events.add);

    socket
      ..receiveTerm(ready)
      ..receiveTerm(const {
        'op': 0,
        's': 2,
        't': 'PRESENCE_UPDATE',
        'd': {
          'user': {'id': _mira},
          'status': 'dnd',
          'client_status': {'mobile': 'online'},
          'guild_id': '123456789012345678',
          'activities': [
            {'name': 'Elden Ring', 'type': 0},
          ],
        },
      });
    await _waitFor(() => events.whereType<PresencesChangedEvent>().isNotEmpty);

    final changed = events.whereType<PresencesChangedEvent>().last.presences;
    expect(changed[_mira]!.status, Presence.doNotDisturb);
    expect(changed[_mira]!.isMobileOnly, isTrue);
    expect(changed[_mira]!.primaryActivity!.name, 'Elden Ring');
  });

  test('a bare-array SESSIONS_REPLACE lands on the presence plane', () async {
    final (repository, socket) = await connect();
    socket.receiveTerm(ready);
    await _waitFor(() => repository.presence!.sessions.isNotEmpty);
    expect(repository.presence!.sessions.single.operatingSystem, 'windows');

    socket.receiveTerm(const {
      'op': 0,
      's': 2,
      't': 'SESSIONS_REPLACE',
      'd': [
        {'session_id': 'phone', 'status': 'idle', 'active': true},
        {'session_id': 'session', 'status': 'online'},
      ],
    });
    await _waitFor(() => repository.presence!.sessions.length == 2);

    expect(repository.presence!.sessions.map((session) => session.sessionId), [
      'phone',
      'session',
    ]);
  });

  test('a bare-array PRESENCES_REPLACE clears the friends who left', () async {
    final (repository, socket) = await connect();
    final events = <ChatRepositoryEvent>[];
    repository.events.listen(events.add);
    socket
      ..receiveTerm(ready)
      ..receiveTerm(const {
        'op': 0,
        's': 2,
        't': 'PRESENCE_UPDATE',
        'd': {
          'user': {'id': _mira},
          'status': 'online',
        },
      });
    await _waitFor(() => events.whereType<PresencesChangedEvent>().isNotEmpty);

    socket.receiveTerm(const {
      'op': 0,
      's': 3,
      't': 'PRESENCES_REPLACE',
      'd': [
        {
          'user': {'id': _roman},
          'status': 'idle',
        },
      ],
    });
    await _waitFor(() => events.whereType<PresencesChangedEvent>().length > 1);

    final changed = events.whereType<PresencesChangedEvent>().last.presences;
    expect(changed[_mira]!.status, Presence.offline);
    expect(changed[_roman]!.status, Presence.idle);
  });

  test('the account broadcasts opcode 3 once the session exists', () async {
    final (repository, socket) = await connect();
    socket.receiveTerm(ready);
    await _waitFor(() => socket.terms.any((frame) => frame['op'] == 3));

    final frame =
        socket.terms.lastWhere((frame) => frame['op'] == 3)['d']!
            as Map<String, Object?>;
    expect(frame.keys, containsAll(['status', 'since', 'activities', 'afk']));
    expect(frame['status'], 'online');
    expect(repository.presence!.selfPresence.status, Presence.online);
  });

  test('the account row is published without any server echo', () async {
    final (repository, socket) = await connect();
    final events = <ChatRepositoryEvent>[];
    repository.events.listen(events.add);

    socket.receiveTerm(ready);
    await _waitFor(() => events.whereType<PresenceChangedEvent>().isNotEmpty);

    // No PRESENCE_UPDATE for the account was ever received, yet the row exists.
    final own = events.whereType<PresenceChangedEvent>().last;
    expect(own.memberId, _me);
    expect(own.presence.status, Presence.online);
    expect(own.presence.clientStatus[ClientPlatform.desktop], Presence.online);
    expect(repository.presence!.selfPresence.status, Presence.online);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

final class _UnusedTransport implements DiscordHttpTransport {
  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async => throw StateError('No REST call is expected');

  @override
  void close() {}
}

final class _MemorySocketConnector implements DiscordDesktopWebSocketConnector {
  _MemorySocketConnector(this.socket);

  final DiscordDesktopWebSocket socket;

  @override
  Future<DiscordDesktopWebSocket> connect(Uri uri) async => socket;
}

final class _MemorySocket implements DiscordDesktopWebSocket {
  final StreamController<Object?> _messages = StreamController();
  final List<Object> sent = [];
  bool _open = true;

  List<Map<String, Object?>> get terms => sent
      .whereType<Uint8List>()
      .map((bytes) => DiscordEtfCodec.decode(bytes)! as Map<String, Object?>)
      .toList(growable: false);

  @override
  int? get closeCode => null;

  @override
  bool get isOpen => _open;

  @override
  Stream<Object?> get messages => _messages.stream;

  void receiveTerm(Map<String, Object?> payload) =>
      _messages.add(DiscordEtfCodec.encode(payload));

  @override
  void send(String data) => sent.add(data);

  @override
  void sendBinary(List<int> data) => sent.add(Uint8List.fromList(data));

  @override
  Future<void> close() async {
    _open = false;
    if (!_messages.isClosed) await _messages.close();
  }
}
