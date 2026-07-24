import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/secure_credential_vault.dart';
import 'package:flucord/src/domain/discord_session.dart';

void main() {
  const codec = DiscordSessionCredentialCodec();

  test('round-trips a versioned bot session credential', () {
    final encoded = codec.encode(DiscordBotSession(' bot-token '));
    final decoded = codec.decode(encoded);

    expect(decoded, isA<DiscordBotSession>());
    expect(decoded?.transportCredential, 'bot-token');
  });

  test('rejects malformed and unknown credential payloads', () {
    expect(codec.decode('not-json'), isNull);
    expect(codec.decode('{"version":2,"kind":"botApplication"}'), isNull);
    expect(codec.decode('{"version":1,"kind":"oauthUser"}'), isNull);
  });

  test('does not persist OAuth access tokens without a refresh store', () {
    final session = DiscordOAuthUserSession(
      accessToken: 'oauth-token',
      scopes: const ['identify'],
      expiresAt: DateTime.utc(2026, 8),
    );

    expect(() => codec.encode(session), throwsUnsupportedError);
  });
}
