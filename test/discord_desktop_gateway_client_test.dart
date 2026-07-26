import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_etf_codec.dart';

void main() {
  test('dials the observed encoding without unsupported compression', () async {
    final socket = _MemoryDesktopWebSocket();
    final connector = _MemoryDesktopWebSocketConnector(socket);
    final gateway = DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      socketConnector: connector,
    );
    addTearDown(gateway.close);

    await gateway.connect('wss://gateway.discord.gg');

    expect(
      connector.uris.single.toString(),
      'wss://gateway.discord.gg?encoding=etf&v=9',
    );
  });

  test('sends an ETF Identify after Gateway Hello', () async {
    final socket = _MemoryDesktopWebSocket();
    final gateway = DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {
        'os': 'Windows',
        'browser': 'Discord Client',
        'device': 'desktop',
      },
      socketConnector: _MemoryDesktopWebSocketConnector(socket),
    );
    addTearDown(gateway.close);

    await gateway.connect('wss://gateway.discord.gg');
    socket.receiveTerm(const {
      'op': 10,
      'd': {'heartbeat_interval': 60000},
    });
    await _waitFor(() => socket.terms.any((frame) => frame['op'] == 2));

    final identify = socket.terms.firstWhere((frame) => frame['op'] == 2);
    final data = identify['d']! as Map<String, Object?>;
    expect(socket.sent.single, isA<Uint8List>());
    expect(data['token'], 'account-session');
    expect(data['capabilities'], 1734653);
    expect(data['properties'], containsPair('os', 'Windows'));
    expect(data['properties'], containsPair('is_fast_connect', false));
  });

  test('builds a typed workspace snapshot from an ETF READY', () async {
    final socket = _MemoryDesktopWebSocket();
    final gateway = DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      socketConnector: _MemoryDesktopWebSocketConnector(socket),
    );
    addTearDown(gateway.close);

    final snapshotFuture = gateway.connectAndReadWorkspace(
      'wss://gateway.discord.gg',
    );
    await Future<void>.delayed(Duration.zero);
    socket.receiveTerm(const {
      'op': 0,
      's': 1,
      't': 'READY',
      'd': {
        'session_id': 'session',
        'resume_gateway_url': 'wss://gateway-resume.discord.gg',
        'user': {'id': 'me', 'username': 'member'},
        'guilds': [
          {'id': 'guild', 'name': 'Guild'},
        ],
        'private_channels': [
          {'id': 'dm', 'type': 1},
        ],
      },
    });

    final snapshot = await snapshotFuture;

    expect(snapshot.currentUser['id'], 'me');
    expect(snapshot.guilds.single['id'], 'guild');
    expect(snapshot.directChannels.single['id'], 'dm');
    expect(
      () => snapshot.guilds.single['name'] = 'changed',
      throwsUnsupportedError,
    );
  });

  test('keeps working when the profile selects the JSON encoding', () async {
    final socket = _MemoryDesktopWebSocket();
    final gateway = DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      profile: const DiscordDesktopProtocolProfile(
        clientBuildNumber: 582977,
        gatewayEncoding: 'json',
      ),
      socketConnector: _MemoryDesktopWebSocketConnector(socket),
    );
    addTearDown(gateway.close);

    await gateway.connect('wss://gateway.discord.gg');
    socket.receiveJson(const {
      'op': 10,
      'd': {'heartbeat_interval': 60000},
    });
    await _waitFor(() => socket.sent.isNotEmpty);

    expect(socket.sent.single, isA<String>());
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

final class _MemoryDesktopWebSocketConnector
    implements DiscordDesktopWebSocketConnector {
  _MemoryDesktopWebSocketConnector(this.socket);

  final DiscordDesktopWebSocket socket;
  final List<Uri> uris = [];

  @override
  Future<DiscordDesktopWebSocket> connect(Uri uri) async {
    uris.add(uri);
    return socket;
  }
}

final class _MemoryDesktopWebSocket implements DiscordDesktopWebSocket {
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

  void receiveJson(Map<String, Object?> payload) =>
      _messages.add(jsonEncode(payload));

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
