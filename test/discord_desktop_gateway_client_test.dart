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
