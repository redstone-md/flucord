import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';

void main() {
  test('uses raw user authorization and only desktop chat routes', () async {
    final transport = _DesktopTransport();
    final client = DiscordDesktopApiClient(
      authorization: 'user-authorization',
      headers: const {'X-Super-Properties': 'desktop-properties'},
      transport: transport,
      baseUri: Uri.parse('https://discord.test/api/v9'),
    );
    addTearDown(client.close);

    await client.getChannelMessages('200');
    await client.createDirectMessageChannel('300');
    expect(await client.getGatewayUrl(), 'wss://gateway.discord.test');

    expect(
      transport.requests.map((request) => request.uri.path),
      containsAllInOrder(const [
        '/api/v9/channels/200/messages',
        '/api/v9/users/@me/channels',
        '/api/v9/gateway',
      ]),
    );
    expect(
      transport.requests.every(
        (request) => request.headers['authorization'] == 'user-authorization',
      ),
      isTrue,
    );
    expect(
      transport.requests.every(
        (request) =>
            request.headers['X-Super-Properties'] == 'desktop-properties',
      ),
      isTrue,
    );
    expect(
      transport.requests.any((request) => request.uri.path.contains('/bot')),
      isFalse,
    );
  });
}

final class _DesktopTransport implements DiscordHttpTransport {
  final List<_Request> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(_Request(uri, Map.unmodifiable({...headers})));
    final Object payload = switch (uri.path) {
      '/api/v9/users/@me' => {'id': '1', 'username': 'demo-user'},
      '/api/v9/users/@me/channels' => {
        'id': '400',
        'type': 1,
        'recipients': const <Object?>[],
      },
      '/api/v9/gateway' => {'url': 'wss://gateway.discord.test'},
      _ => const <Object?>[],
    };
    return DiscordHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(payload),
    );
  }

  @override
  void close() {}
}

final class _Request {
  const _Request(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
}
