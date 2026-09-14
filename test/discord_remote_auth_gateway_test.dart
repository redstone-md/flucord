import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_remote_auth_api.dart';
import 'package:flucord/src/data/discord/discord_remote_auth_gateway.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';

void main() {
  test('negotiates hello and publishes the remote-auth QR URI', () async {
    final socket = _MemoryRemoteAuthSocket();
    final gateway = DiscordRemoteAuthGatewayClient(
      connectSocket: (_) async => socket,
    );
    addTearDown(gateway.close);

    await gateway.start();
    socket.receive(
      jsonEncode(const {'op': 'hello', 'heartbeat_interval': 60000}),
    );
    await _waitFor(() => socket.sent.isNotEmpty);

    final init = jsonDecode(socket.sent.single) as Map<String, Object?>;
    expect(init['op'], 'init');
    expect(
      init['encoded_public_key'],
      isA<String>().having((value) => value.length, 'length', greaterThan(300)),
    );

    final qrEvent = gateway.events
        .firstWhere((event) => event is DiscordRemoteAuthQrReady)
        .then((event) => event as DiscordRemoteAuthQrReady);
    socket.receive(
      jsonEncode(const {
        'op': 'pending_remote_init',
        'fingerprint': 'gateway-fingerprint',
      }),
    );

    expect(
      (await qrEvent).qrUri,
      Uri.parse('https://discord.com/ra/gateway-fingerprint'),
    );
  });

  test('retains the pending ticket and retries it after hCaptcha', () async {
    final socket = _MemoryRemoteAuthSocket();
    final transport = _CaptchaRemoteAuthTransport();
    final api = DiscordRemoteAuthApiClient(
      transport: transport,
      baseUri: Uri.parse('https://discord.test/api/v9'),
    );
    final gateway = DiscordRemoteAuthGatewayClient(
      api: api,
      connectSocket: (_) async => socket,
    );
    addTearDown(gateway.close);
    await gateway.start();

    final firstChallenge = gateway.events
        .firstWhere((event) => event is DiscordRemoteAuthCaptchaRequired)
        .then((event) => event as DiscordRemoteAuthCaptchaRequired);
    socket.receive(
      jsonEncode(const {'op': 'pending_login', 'ticket': 'remote-ticket'}),
    );
    expect((await firstChallenge).challenge.rqToken, 'request-token-1');

    final secondChallenge = gateway.events
        .firstWhere((event) => event is DiscordRemoteAuthCaptchaRequired)
        .then((event) => event as DiscordRemoteAuthCaptchaRequired);
    await gateway.submitCaptcha('captcha-solution');
    expect((await secondChallenge).challenge.rqToken, 'request-token-2');

    final retry = transport.requests.last;
    expect(jsonDecode(utf8.decode(retry.body!)), {'ticket': 'remote-ticket'});
    expect(retry.headers['X-Captcha-Key'], 'captcha-solution');
    expect(retry.headers['X-Captcha-Rqtoken'], 'request-token-1');
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

final class _MemoryRemoteAuthSocket implements DiscordDesktopWebSocket {
  final StreamController<Object?> _messages = StreamController();
  final List<String> sent = [];
  bool _open = true;

  @override
  bool get isOpen => _open;

  @override
  int? get closeCode => null;

  @override
  Stream<Object?> get messages => _messages.stream;

  void receive(String message) => _messages.add(message);

  @override
  void send(String data) => sent.add(data);

  @override
  void sendBinary(List<int> data) =>
      throw UnsupportedError('Remote auth Gateway v2 is a text protocol');

  @override
  Future<void> close() async {
    _open = false;
    if (!_messages.isClosed) await _messages.close();
  }
}

final class _CaptchaRemoteAuthTransport implements DiscordHttpTransport {
  final List<_RemoteAuthRequest> requests = [];
  var _challengeNumber = 0;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(_RemoteAuthRequest(Map.of(headers), body));
    if (uri.path.endsWith('/experiments')) {
      return const DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body: '{"fingerprint":"api-fingerprint"}',
      );
    }
    _challengeNumber++;
    return DiscordHttpResponse(
      statusCode: 400,
      headers: const {},
      body: jsonEncode({
        'captcha_key': ['captcha-required'],
        'captcha_sitekey': 'site-key',
        'captcha_service': 'hcaptcha',
        'captcha_rqdata': 'request-data-$_challengeNumber',
        'captcha_rqtoken': 'request-token-$_challengeNumber',
      }),
    );
  }

  @override
  void close() {}
}

final class _RemoteAuthRequest {
  const _RemoteAuthRequest(this.headers, this.body);

  final Map<String, String> headers;
  final List<int>? body;
}
