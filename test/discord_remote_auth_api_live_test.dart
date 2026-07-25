import 'dart:io';

import 'package:flucord/src/data/discord/discord_remote_auth_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receives a fingerprint from the live experiments endpoint', () async {
    if (Platform.environment['FLUCORD_LIVE_REMOTE_AUTH_API_TEST'] != '1') {
      markTestSkipped('Set FLUCORD_LIVE_REMOTE_AUTH_API_TEST=1 to enable.');
    }
    final client = DiscordRemoteAuthApiClient();
    addTearDown(client.close);

    final fingerprint = await client.prepareFingerprint();

    expect(fingerprint, isNotEmpty);
  });
}
