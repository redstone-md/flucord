import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_oauth_token_client.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/discord_oauth.dart';

void main() {
  test('exchanges a PKCE code as a public client without a secret', () async {
    final transport = _RecordingTransport(const [
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '{"token_type":"Bearer","access_token":"access-1",'
            '"refresh_token":"refresh-1","expires_in":3600,'
            '"scope":"identify guilds"}',
      ),
    ]);
    final client = DiscordOAuthTokenClient(
      transport: transport,
      clock: () => DateTime.utc(2026, 7, 24, 4),
    );

    final grant = await client.exchangeCode(
      clientId: 'application-1',
      code: 'authorization-code',
      redirectUri: Uri.parse('flucord://oauth/discord/callback'),
      codeVerifier: 'pkce-verifier',
    );

    expect(grant.accessToken, 'access-1');
    expect(grant.refreshToken, 'refresh-1');
    expect(grant.scopes, {'identify', 'guilds'});
    expect(grant.expiresAt, DateTime.utc(2026, 7, 24, 5));
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v10/oauth2/token');
    expect(
      request.headers['content-type'],
      'application/x-www-form-urlencoded',
    );
    expect(request.headers, isNot(contains('authorization')));
    final form = Uri.splitQueryString(utf8.decode(request.body));
    expect(form['client_id'], 'application-1');
    expect(form['grant_type'], 'authorization_code');
    expect(form['code'], 'authorization-code');
    expect(form['code_verifier'], 'pkce-verifier');
    expect(form, isNot(contains('client_secret')));
  });

  test('rotates a refresh token and retains scopes when omitted', () async {
    final transport = _RecordingTransport(const [
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '{"token_type":"Bearer","access_token":"access-2",'
            '"refresh_token":"refresh-2","expires_in":1800}',
      ),
    ]);
    final client = DiscordOAuthTokenClient(
      transport: transport,
      clock: () => DateTime.utc(2026, 7, 24, 4),
    );
    final current = DiscordOAuthGrant(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      scopes: const {'identify', 'guilds'},
      expiresAt: DateTime.utc(2026, 7, 24, 4),
    );

    final refreshed = await client.refresh(
      clientId: 'application-1',
      currentGrant: current,
    );

    expect(refreshed.accessToken, 'access-2');
    expect(refreshed.refreshToken, 'refresh-2');
    expect(refreshed.scopes, current.scopes);
    final form = Uri.splitQueryString(
      utf8.decode(transport.requests.single.body),
    );
    expect(form['grant_type'], 'refresh_token');
    expect(form['refresh_token'], 'refresh-1');
    expect(form, isNot(contains('client_secret')));
  });

  test('redacts both OAuth grant secrets', () {
    final grant = DiscordOAuthGrant(
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
      scopes: const {'identify'},
      expiresAt: DateTime.utc(2026, 7, 24, 5),
    );

    expect(grant.toString(), contains('<redacted>'));
    expect(grant.toString(), isNot(contains('access-secret')));
    expect(grant.toString(), isNot(contains('refresh-secret')));
  });
}

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
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
      _RecordedRequest(
        method: method,
        uri: uri,
        headers: Map.unmodifiable(headers),
        body: List.unmodifiable(body ?? const []),
      ),
    );
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
