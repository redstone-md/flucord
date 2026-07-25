import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';

void main() {
  final enabled = Platform.environment['FLUCORD_LIVE_GATEWAY_TEST'] == '1';

  test(
    'receives Hello from the live desktop Gateway',
    () async {
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
    },
    skip: enabled ? false : 'Set FLUCORD_LIVE_GATEWAY_TEST=1.',
  );
}
