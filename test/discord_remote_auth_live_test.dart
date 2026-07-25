import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_remote_auth_gateway.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';

void main() {
  final enabled = Platform.environment['FLUCORD_LIVE_REMOTE_AUTH_TEST'] == '1';

  test(
    'receives a QR fingerprint from the live remote-auth Gateway',
    () async {
      final gateway = DiscordRemoteAuthGatewayClient();
      addTearDown(gateway.close);
      final firstEvent = gateway.events.first.timeout(
        const Duration(seconds: 20),
      );

      await gateway.start();
      final event = await firstEvent;

      if (event is DiscordRemoteAuthFailed) {
        fail(event.message);
      }
      expect(event, isA<DiscordRemoteAuthQrReady>());
      final qr = event as DiscordRemoteAuthQrReady;
      expect(qr.fingerprint, isNotEmpty);
      expect(qr.qrUri.scheme, 'https');
      expect(qr.qrUri.host, 'discord.com');
      expect(qr.qrUri.pathSegments.first, 'ra');
    },
    skip: enabled ? false : 'Set FLUCORD_LIVE_REMOTE_AUTH_TEST=1.',
  );
}
