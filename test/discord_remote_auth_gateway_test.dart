import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_remote_auth_gateway.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';

void main() {
  test('negotiates hello and publishes the remote-auth QR URI', () async {
    final socket = _MemoryRemoteAuthSocket();
    final gateway = DiscordRemoteAuthGatewayClient(
      connectSocket: (_) async => socket,
    );
    addTearDown(gateway.close);

    await gateway.start();
    socket.receive(
      jsonEncode(const {'op': 'hello', 'heartbeat_interval': 60000}),
    );
    await _waitFor(() => socket.sent.isNotEmpty);

    final init = jsonDecode(socket.sent.single) as Map<String, Object?>;
    expect(init['op'], 'init');
    expect(
      init['encoded_public_key'],
      isA<String>().having((value) => value.length, 'length', greaterThan(300)),
    );

    final qrEvent = gateway.events
        .firstWhere((event) => event is DiscordRemoteAuthQrReady)
        .then((event) => event as DiscordRemoteAuthQrReady);
    socket.receive(
      jsonEncode(const {
        'op': 'pending_remote_init',
        'fingerprint': 'gateway-fingerprint',
      }),
    );

    expect(
      (await qrEvent).qrUri,
      Uri.parse('https://discord.com/ra/gateway-fingerprint'),
    );
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

final class _MemoryRemoteAuthSocket implements DiscordDesktopWebSocket {
  final StreamController<Object?> _messages = StreamController();
  final List<String> sent = [];
  bool _open = true;

  @override
  bool get isOpen => _open;

  @override
  int? get closeCode => null;

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
