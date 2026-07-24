import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/secure_discord_oauth_vault.dart';
import 'package:flucord/src/domain/discord_oauth.dart';

void main() {
  const codec = DiscordOAuthGrantCodec();

  test('round-trips a refreshable OAuth grant', () {
    final encoded = codec.encode(
      DiscordOAuthGrant(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        scopes: const {'identify', 'guilds'},
        expiresAt: DateTime.utc(2026, 7, 24, 5),
      ),
    );
    final decoded = codec.decode(encoded)!;

    expect(decoded.accessToken, 'access-token');
    expect(decoded.refreshToken, 'refresh-token');
    expect(decoded.scopes, {'identify', 'guilds'});
    expect(decoded.expiresAt, DateTime.utc(2026, 7, 24, 5));
  });

  test('rejects malformed, incomplete, and unknown versions', () {
    expect(codec.decode('not-json'), isNull);
    expect(codec.decode('{"version":2}'), isNull);
    expect(codec.decode('{"version":1,"access_token":"only"}'), isNull);
  });
}
