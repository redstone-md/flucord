import 'dart:io';

import 'package:flucord/src/data/discord/discord_remote_auth_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled =
      Platform.environment['FLUCORD_LIVE_REMOTE_AUTH_API_TEST'] == '1';

  test(
    'receives a fingerprint from the live experiments endpoint',
    () async {
      final client = DiscordRemoteAuthApiClient();
      addTearDown(client.close);

      final fingerprint = await client.prepareFingerprint();

      expect(fingerprint, isNotEmpty);
    },
    // `skip:` rather than markTestSkipped inside the body: the latter records
    // the skip and then runs the body anyway, so this test called Discord on
    // every CI run and failed the release when Cloudflare rate-limited the
    // runner. The gateway test beside it was already written this way.
    skip: enabled ? false : 'Set FLUCORD_LIVE_REMOTE_AUTH_API_TEST=1.',
  );
}
