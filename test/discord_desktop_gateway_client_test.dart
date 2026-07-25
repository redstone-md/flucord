import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';

void main() {
  test('sends desktop Identify after Gateway Hello', () async {
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
    socket.receive(
      jsonEncode(const {
        'op': 10,
        'd': {'heartbeat_interval': 60000},
      }),
    );
    await _waitFor(() => socket.sent.any((raw) => jsonDecode(raw)['op'] == 2));

    final identify = socket.sent
        .map((raw) => jsonDecode(raw) as Map<String, Object?>)
        .firstWhere((payload) => payload['op'] == 2);
    final data = identify['d']! as Map<String, Object?>;
    expect(data['token'], 'account-session');
    expect(data['properties'], containsPair('os', 'Windows'));
  });

  test('builds a typed workspace snapshot from READY', () async {
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
    socket.receive(
      jsonEncode(const {
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
      }),
    );

    final snapshot = await snapshotFuture;

    expect(snapshot.currentUser['id'], 'me');
    expect(snapshot.guilds.single['id'], 'guild');
    expect(snapshot.directChannels.single['id'], 'dm');
    expect(
      () => snapshot.guilds.single['name'] = 'changed',
      throwsUnsupportedError,
    );
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
  const _MemoryDesktopWebSocketConnector(this.socket);

  final DiscordDesktopWebSocket socket;

  @override
  Future<DiscordDesktopWebSocket> connect(Uri uri) async => socket;
}

final class _MemoryDesktopWebSocket implements DiscordDesktopWebSocket {
  final StreamController<Object?> _messages = StreamController();
  final List<String> sent = [];
  bool _open = true;

  @override
  int? get closeCode => null;

  @override
  bool get isOpen => _open;

  @override
  Stream<Object?> get messages => _messages.stream;

  void receive(String message) => _messages.add(message);

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    _open = false;
    if (!_messages.isClosed) await _messages.close();
  }
}
