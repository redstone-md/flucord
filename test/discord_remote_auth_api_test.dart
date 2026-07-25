import 'dart:convert';

import 'package:flucord/src/data/discord/discord_remote_auth_api.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prepares a fingerprint before exchanging a remote-auth ticket',
    () async {
      final transport = _RemoteAuthTransport();
      final client = DiscordRemoteAuthApiClient(
        transport: transport,
        baseUri: Uri.parse('https://discord.test/api/v9'),
      );
      addTearDown(client.close);

      expect(await client.exchangeTicket('remote-ticket'), 'encrypted-token');

      expect(transport.requests, hasLength(2));
      expect(transport.requests.first.method, 'GET');
      expect(transport.requests.first.uri.path, '/api/v9/experiments');
      final exchange = transport.requests.last;
      expect(exchange.method, 'POST');
      expect(exchange.uri.path, '/api/v9/users/@me/remote-auth/login');
      expect(exchange.headers['X-Fingerprint'], 'api-fingerprint');
      expect(exchange.headers['X-Super-Properties'], isNotEmpty);
      expect(exchange.headers['user-agent'], contains('discord/1.0.9249'));
      expect(jsonDecode(utf8.decode(exchange.body!)), {
        'ticket': 'remote-ticket',
      });
    },
  );

  test(
    'sends the hCaptcha solution with the original challenge token',
    () async {
      final transport = _RemoteAuthTransport();
      final client = DiscordRemoteAuthApiClient(
        transport: transport,
        baseUri: Uri.parse('https://discord.test/api/v9'),
      );
      addTearDown(client.close);

      await client.exchangeTicket(
        'remote-ticket',
        captchaKey: 'captcha-solution',
        captchaRqtoken: 'captcha-request-token',
        captchaSessionId: 'captcha-session-id',
      );

      expect(jsonDecode(utf8.decode(transport.requests.last.body!)), {
        'ticket': 'remote-ticket',
      });
      expect(
        transport.requests.last.headers['X-Captcha-Key'],
        'captcha-solution',
      );
      expect(
        transport.requests.last.headers['X-Captcha-Rqtoken'],
        'captcha-request-token',
      );
      expect(
        transport.requests.last.headers['X-Captcha-Session-Id'],
        'captcha-session-id',
      );
    },
  );

  test('parses a structured Discord hCaptcha challenge', () {
    final client = DiscordRemoteAuthApiClient(
      transport: _RemoteAuthTransport(),
      baseUri: Uri.parse('https://discord.test/api/v9'),
    );
    addTearDown(client.close);
    final challenge = client.captchaChallengeFrom(
      const DiscordApiException(
        statusCode: 400,
        message: 'captcha_key: captcha-required',
        responsePayload: {
          'captcha_key': ['captcha-required'],
          'captcha_sitekey': 'site-key',
          'captcha_service': 'hcaptcha',
          'captcha_rqdata': 'request-data',
          'captcha_rqtoken': 'request-token',
          'captcha_session_id': 'session-id',
          'should_serve_invisible': true,
        },
      ),
    );

    expect(challenge, isNotNull);
    expect(challenge!.siteKey, 'site-key');
    expect(challenge.service, 'hcaptcha');
    expect(challenge.userAgent, contains('discord/1.0.9249'));
    expect(challenge.rqData, 'request-data');
    expect(challenge.rqToken, 'request-token');
    expect(challenge.sessionId, 'session-id');
    expect(challenge.serveInvisible, isTrue);
    expect(challenge.toString(), isNot(contains('request-data')));

    final retryChallenge = client.captchaChallengeFrom(
      const DiscordApiException(
        statusCode: 400,
        message: 'captcha_key: invalid-response',
        responsePayload: {
          'captcha_key': ['invalid-response'],
          'captcha_sitekey': 'site-key-2',
          'captcha_service': 'hcaptcha',
        },
      ),
    );
    expect(retryChallenge?.siteKey, 'site-key-2');
  });

  test('surfaces form errors without exposing token-like values', () async {
    final executor = DiscordHttpExecutor(
      transport: _RemoteAuthTransport(
        response: const DiscordHttpResponse(
          statusCode: 400,
          headers: {},
          body:
              '{"code":50035,"ticket":["Invalid remote authentication ticket."],"opaque":"abcdefghijklmnopqrstuvwxyz0123456789"}',
        ),
      ),
      baseUri: Uri.parse('https://discord.test/api/v9'),
    );

    await expectLater(
      executor.execute('GET', '/failure', headers: const {}),
      throwsA(
        isA<DiscordApiException>()
            .having(
              (error) => error.message,
              'form details',
              contains('ticket: Invalid remote authentication ticket.'),
            )
            .having(
              (error) => error.message,
              'redacted opaque value',
              isNot(contains('abcdefghijklmnopqrstuvwxyz0123456789')),
            ),
      ),
    );
  });
}

final class _RemoteAuthTransport implements DiscordHttpTransport {
  _RemoteAuthTransport({this.response});

  final DiscordHttpResponse? response;
  final List<_Request> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(_Request(method, uri, Map.of(headers), body));
    if (response != null) return response!;
    return DiscordHttpResponse(
      statusCode: 200,
      headers: const {},
      body: uri.path.endsWith('/experiments')
          ? '{"fingerprint":"api-fingerprint"}'
          : '{"encrypted_token":"encrypted-token"}',
    );
  }

  @override
  void close() {}
}

final class _Request {
  const _Request(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? body;
}
