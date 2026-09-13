import 'dart:async';
import 'dart:io';

import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Uri uri;
  final heldRequests = <HttpRequest>[];

  setUp(() async {
    heldRequests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    uri = Uri.parse('http://${server.address.host}:${server.port}/api/v10/ping');
    // Accepting and never answering is the hang the transport has to survive.
    server.listen(heldRequests.add);
    addTearDown(server.close);
  });

  /// A transport with a timeout short enough to test against.
  Future<IoDiscordHttpTransport> transport() async {
    final instance = IoDiscordHttpTransport(
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(instance.close);
    return instance;
  }

  test('a server that never answers times the request out', () async {
    final instance = await transport();

    await expectLater(
      instance.send(method: 'GET', uri: uri, headers: const {}),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a response body that never finishes times the request out', () async {
    final instance = await transport();
    final headersServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(headersServer.close);
    // Headers arrive, the body never does.
    headersServer.listen((request) {
      request.response.headers.contentLength = 64;
      request.response.add([1]);
    });

    await expectLater(
      instance.send(
        method: 'GET',
        uri: Uri.parse(
          'http://${headersServer.address.host}:${headersServer.port}/x',
        ),
        headers: const {},
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('the hung request is aborted, releasing the connection', () async {
    final instance = await transport();
    // A raw socket is the honest witness: an HTTP server that never answered
    // reports a vanished client lazily, but the TCP close is immediate.
    final rawServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(rawServer.close);
    final connectionClosed = Completer<void>();
    rawServer.listen((socket) {
      socket.listen(
        (_) {},
        onDone: connectionClosed.complete,
        onError: connectionClosed.complete,
      );
    });

    await expectLater(
      instance.send(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${rawServer.port}/x'),
        headers: const {},
      ),
      throwsA(isA<TimeoutException>()),
    );

    await connectionClosed.future.timeout(const Duration(seconds: 2));
  });

  test('the transport still works after a timeout', () async {
    final instance = await transport();

    await expectLater(
      instance.send(method: 'GET', uri: uri, headers: const {}),
      throwsA(isA<TimeoutException>()),
    );

    final answering = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(answering.close);
    answering.listen((request) async {
      await request.response.close();
    });

    final response = await instance.send(
      method: 'GET',
      uri: Uri.parse(
        'http://${answering.address.host}:${answering.port}/ok',
      ),
      headers: const {},
    );
    expect(response.statusCode, 200);
  });
}
