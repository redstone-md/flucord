import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_gateway_framing.dart';

void main() {
  final enabled = Platform.environment['FLUCORD_LIVE_GATEWAY_TEST'] == '1';
  final skip = enabled ? null : 'Set FLUCORD_LIVE_GATEWAY_TEST=1.';

  test('receives Hello from the live desktop Gateway', () async {
    final socket = await const PlatformDiscordDesktopWebSocketConnector()
        .connect(Uri.parse('wss://gateway.discord.gg/?encoding=json&v=9'));
    addTearDown(socket.close);

    final raw = await socket.messages.first.timeout(
      const Duration(seconds: 20),
    );
    expect(raw, isA<String>());
    final payload = jsonDecode(raw! as String) as Map<String, Object?>;
    expect(payload['op'], 10);
    expect(payload['d'], contains('heartbeat_interval'));
  }, skip: skip);

  test('decodes a live ETF Hello with the desktop framing', () async {
    const profile = DiscordDesktopProtocolProfile.installedStable20260725;
    final uri = profile.connectionUri();
    expect(uri.queryParameters['encoding'], 'etf');
    expect(uri.queryParameters.containsKey('compress'), isFalse);

    final socket = await const PlatformDiscordDesktopWebSocketConnector()
        .connect(uri);
    addTearDown(socket.close);

    final raw = await socket.messages.first.timeout(
      const Duration(seconds: 20),
    );
    expect(raw, isA<Uint8List>());

    final payload = const DiscordGatewayEtfFraming().decode(raw);
    expect(payload, isNotNull);
    expect(payload!['op'], 10);
    expect(payload['d'], isA<Map<String, Object?>>());
    expect(
      (payload['d']! as Map<String, Object?>)['heartbeat_interval'],
      isA<int>(),
    );
  }, skip: skip);

  test('gets a live ACK for an ETF heartbeat Flucord encoded', () async {
    const profile = DiscordDesktopProtocolProfile.installedStable20260725;
    const framing = DiscordGatewayEtfFraming();
    final socket = await const PlatformDiscordDesktopWebSocketConnector()
        .connect(profile.connectionUri());
    addTearDown(socket.close);

    final frames = <Map<String, Object?>>[];
    final subscription = socket.messages.listen((raw) {
      final payload = framing.decode(raw);
      if (payload != null) frames.add(payload);
    });
    addTearDown(subscription.cancel);

    // No credential is involved: Discord acknowledges a heartbeat before
    // Identify, so an opcode 11 reply proves the server unpacked the exact
    // ETF frame Flucord encoded.
    socket.sendBinary(framing.encode(const {'op': 1, 'd': null}) as Uint8List);

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (socket.isOpen &&
        !frames.any((frame) => frame['op'] == 11) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(frames.first['op'], 10);
    expect(frames.map((frame) => frame['op']), contains(11));
  }, skip: skip);
}
