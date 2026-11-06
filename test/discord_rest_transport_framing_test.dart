import 'dart:convert';
import 'dart:io';

import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';

void main() {
  test('a body goes out with a fixed length, never chunked', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final seen = <(String, int, bool)>[];
    server.listen((request) async {
      final bytes = await request.fold<int>(
        0,
        (sum, part) => sum + part.length,
      );
      seen.add((
        request.method,
        request.contentLength,
        request.headers.chunkedTransferEncoding,
      ));
      expect(bytes, request.contentLength);
      request.response.statusCode = 204;
      await request.response.close();
    });
    final transport = IoDiscordHttpTransport();
    addTearDown(transport.close);
    final uri = Uri.parse('http://127.0.0.1:${server.port}/api/v10/ring');

    final body = utf8.encode('{"recipients":null}');
    await transport.send(
      method: 'POST',
      uri: uri,
      headers: const {},
      body: body,
    );
    await transport.send(method: 'POST', uri: uri, headers: const {});

    expect(seen, [('POST', body.length, false), ('POST', 0, false)]);
  });

  test('an empty raw body claims no content type', () async {
    final transport = FakeDiscordTransport(
      fallback: (_) => jsonResponse(const {}),
    );
    final client = DiscordRestClient(
      authorization: DiscordBotAuthorization('token'),
      transport: transport,
    );
    addTearDown(client.close);

    await client.request('POST', '/channels/1/typing', rawBody: const []);

    expect(transport.requests.single.headers, isNot(contains('content-type')));
  });
}
