import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_oauth_identity_client.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/discord_session.dart';

void main() {
  group('Discord REST authorization', () {
    test('redacts Bot and Bearer credentials', () {
      final bot = DiscordBotAuthorization('bot-secret');
      final bearer = DiscordBearerAuthorization('oauth-secret');
      final rest = DiscordRestClient(
        authorization: bearer,
        transport: _RecordingTransport(const []),
      );

      expect(bot.toString(), contains('<redacted>'));
      expect(bot.toString(), isNot(contains('bot-secret')));
      expect(bearer.toString(), contains('<redacted>'));
      expect(bearer.toString(), isNot(contains('oauth-secret')));
      expect(rest.toString(), isNot(contains('oauth-secret')));
    });

    test('rejects empty credentials', () {
      expect(() => DiscordBotAuthorization('  '), throwsArgumentError);
      expect(() => DiscordBearerAuthorization('\n'), throwsArgumentError);
    });
  });

  group('DiscordOAuthIdentityClient', () {
    test('uses Bearer only for documented identity and guild routes', () async {
      final transport = _RecordingTransport(const [
        DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body: '{"id":"user-1","username":"Jack"}',
        ),
        DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body: '[{"id":"guild-1","name":"The Forge"}]',
        ),
        DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body: '{"user":{"id":"user-1"},"roles":[]}',
        ),
      ]);
      final client = DiscordOAuthIdentityClient(
        session: _session(
          scopes: const {'identify', 'guilds', 'guilds.members.read'},
        ),
        transport: transport,
      );

      final user = await client.getCurrentUser();
      final guilds = await client.getCurrentUserGuilds();
      final membership = await client.getCurrentUserGuildMember(
        '123456789012345678',
      );

      expect(user['id'], 'user-1');
      expect(guilds.single['id'], 'guild-1');
      expect(membership['roles'], isEmpty);
      expect(transport.requests, hasLength(3));
      for (final request in transport.requests) {
        expect(request.headers['authorization'], 'Bearer oauth-secret');
        expect(request.headers, isNot(contains('x-super-properties')));
        expect(request.headers, isNot(contains('x-fingerprint')));
      }
      expect(transport.requests[0].uri.path, '/api/v10/users/@me');
      expect(transport.requests[1].uri.path, '/api/v10/users/@me/guilds');
      expect(transport.requests[1].uri.queryParameters['limit'], '200');
      expect(transport.requests[1].uri.queryParameters['with_counts'], 'true');
      expect(
        transport.requests[2].uri.path,
        '/api/v10/users/@me/guilds/123456789012345678/member',
      );
    });

    test('rejects a route when its OAuth scope is absent', () async {
      final transport = _RecordingTransport(const []);
      final client = DiscordOAuthIdentityClient(
        session: _session(scopes: const {'identify'}),
        transport: transport,
      );

      await expectLater(
        client.getCurrentUserGuilds(),
        throwsA(
          isA<DiscordOAuthCapabilityException>().having(
            (error) => error.capability,
            'capability',
            DiscordSessionCapability.guildDirectory,
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    });

    test('rejects an expired session before network access', () async {
      final transport = _RecordingTransport(const []);
      final client = DiscordOAuthIdentityClient(
        session: DiscordOAuthUserSession(
          accessToken: 'oauth-secret',
          scopes: const {'identify'},
          expiresAt: DateTime.utc(2000),
        ),
        transport: transport,
      );

      await expectLater(
        client.getCurrentUser(),
        throwsA(isA<DiscordOAuthSessionExpiredException>()),
      );
      expect(transport.requests, isEmpty);
    });
  });
}

DiscordOAuthUserSession _session({required Set<String> scopes}) =>
    DiscordOAuthUserSession(
      accessToken: 'oauth-secret',
      scopes: scopes,
      expiresAt: DateTime.utc(2100),
    );

final class _RecordedRequest {
  const _RecordedRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

final class _RecordingTransport implements DiscordHttpTransport {
  _RecordingTransport(List<DiscordHttpResponse> responses)
    : _responses = [...responses];

  final List<DiscordHttpResponse> _responses;
  final List<_RecordedRequest> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(
      _RecordedRequest(uri: uri, headers: Map.unmodifiable(headers)),
    );
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
