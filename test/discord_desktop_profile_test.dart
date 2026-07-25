import 'dart:convert';

import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DiscordDesktopSuperProperties properties() => DiscordDesktopSuperProperties(
    os: 'Windows',
    systemLocale: 'en-US',
    browserUserAgent: 'test-agent',
    browserVersion: '37.6.1',
    osVersion: '10.0.26100',
    releaseChannel: 'stable',
    clientBuildNumber: 582977,
    nativeBuildNumber: 9249,
    clientLaunchId: 'launch-id',
  );

  test('installed profile builds the observed REST and Gateway endpoints', () {
    const profile = DiscordDesktopProtocolProfile.installedStable20260725;

    expect(profile.apiBaseUri.toString(), 'https://discord.com/api/v9');
    expect(
      profile.gatewayUri().toString(),
      'wss://gateway.discord.gg?encoding=etf&v=9&compress=zstd-stream',
    );
  });

  test('super properties use the renderer bundle field names', () {
    final decoded =
        jsonDecode(utf8.decode(base64Decode(properties().toBase64())))
            as Map<String, Object?>;

    expect(decoded['browser'], 'Discord Client');
    expect(decoded['client_build_number'], 582977);
    expect(decoded['has_client_mods'], isFalse);
    expect(decoded['client_launch_id'], 'launch-id');
  });

  test('request headers match the desktop request preparation surface', () {
    final headers = DiscordDesktopRequestHeaders(
      authorization: 'secret-value',
      superProperties: properties(),
      locale: 'en-US',
      fingerprint: 'fingerprint',
      installationId: 'installation',
      acceptLanguage: 'en-US,en;q=0.9',
      timezone: 'Europe/Budapest',
      debugOptions: 'debug',
      routingKey: 'routing',
      clientTraceId: 'trace',
    );

    expect(headers.build(), containsPair('Authorization', 'secret-value'));
    expect(headers.build(), containsPair('X-Fingerprint', 'fingerprint'));
    expect(headers.build(), containsPair('X-Installation-ID', 'installation'));
    expect(headers.build(), containsPair('X-Discord-Locale', 'en-US'));
    expect(
      headers.build(),
      containsPair('X-Discord-Timezone', 'Europe/Budapest'),
    );
    expect(headers.build(), containsPair('X-Debug-Options', 'debug'));
    expect(headers.build(), containsPair('X-Routing-Key', 'routing'));
    expect(headers.build(), containsPair('x-client-trace-id', 'trace'));
    expect(
      () => headers.build()['Authorization'] = 'changed',
      throwsUnsupportedError,
    );
    expect(headers.toString(), isNot(contains('secret-value')));
  });
}
