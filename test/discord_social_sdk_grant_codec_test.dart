import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/secure_discord_social_sdk_vault.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  const codec = DiscordSocialSdkGrantCodec();

  test('round-trips a versioned Social SDK grant without logging secrets', () {
    final grant = DiscordSocialSdkGrant(
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
      expiresAt: DateTime.utc(2026, 2, 22, 4, 47),
      scopes: const ['identify', 'relationships.read'],
    );

    final decoded = codec.decode(codec.encode(grant));

    expect(decoded?.accessToken, 'access-secret');
    expect(decoded?.refreshToken, 'refresh-secret');
    expect(decoded?.expiresAt, DateTime.utc(2026, 2, 22, 4, 47));
    expect(decoded?.scopes, {'identify', 'relationships.read'});
    expect(decoded.toString(), 'DiscordSocialSdkGrant(<redacted>)');
  });

  test('rejects malformed and unknown grant records', () {
    expect(codec.decode('not json'), isNull);
    expect(codec.decode('{"version":2}'), isNull);
    expect(
      codec.decode(
        '{"version":1,"access_token":"","refresh_token":"x",'
        '"expires_at":"2026-02-22T04:47:00Z","scopes":[]}',
      ),
      isNull,
    );
  });
}
