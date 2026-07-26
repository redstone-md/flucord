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

  test('reads and writes the settings proto route', () async {
    final transport = _DesktopTransport();
    final client = DiscordDesktopApiClient(
      authorization: 'user-authorization',
      headers: const {},
      transport: transport,
      baseUri: Uri.parse('https://discord.test/api/v9'),
    );
    addTearDown(client.close);

    expect(await client.readSettingsProto(1), 'CgIIAQ==');
    final written = await client.writeSettingsProto(
      type: 1,
      settings: 'CgIIAg==',
    );

    expect(written.settings, 'CgIIAw==');
    expect(written.outOfDate, isTrue);
    expect(
      transport.requests.map((request) => request.uri.path),
      containsAllInOrder(const [
        '/api/v9/users/@me/settings-proto/1',
        '/api/v9/users/@me/settings-proto/1',
      ]),
    );
    expect(transport.requests.last.body, contains('CgIIAg=='));
  });

  test('answers null when the account stores no settings', () async {
    final transport = _DesktopTransport(settings: null);
    final client = DiscordDesktopApiClient(
      authorization: 'user-authorization',
      headers: const {},
      transport: transport,
      baseUri: Uri.parse('https://discord.test/api/v9'),
    );
    addTearDown(client.close);

    expect(await client.readSettingsProto(2), isNull);
    expect(
      (await client.writeSettingsProto(type: 2, settings: 'CgA=')).settings,
      isNull,
    );
  });

  test('refuses a settings type Discord does not define', () async {
    final client = DiscordDesktopApiClient(
      authorization: 'user-authorization',
      headers: const {},
      transport: _DesktopTransport(),
      baseUri: Uri.parse('https://discord.test/api/v9'),
    );
    addTearDown(client.close);

    expect(() => client.readSettingsProto(0), throwsArgumentError);
    expect(
      () => client.writeSettingsProto(type: 4, settings: 'CgA='),
      throwsArgumentError,
    );
  });
}

final class _DesktopTransport implements DiscordHttpTransport {
  _DesktopTransport({this.settings = 'CgIIAQ=='});

  final String? settings;
  final List<_Request> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(
      _Request(
        uri,
        Map.unmodifiable({...headers}),
        body == null ? '' : utf8.decode(body),
      ),
    );
    final Object payload = switch (uri.path) {
      '/api/v9/users/@me' => {'id': '1', 'username': 'demo-user'},
      '/api/v9/users/@me/channels' => {
        'id': '400',
        'type': 1,
        'recipients': const <Object?>[],
      },
      '/api/v9/gateway' => {'url': 'wss://gateway.discord.test'},
      '/api/v9/users/@me/settings-proto/1' =>
        method == 'PATCH'
            ? {'settings': 'CgIIAw==', 'out_of_date': true}
            : {'settings': settings},
      '/api/v9/users/@me/settings-proto/2' => {'settings': settings},
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
  const _Request(this.uri, this.headers, this.body);

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}
