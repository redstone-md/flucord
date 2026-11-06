import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_rest_client.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _sendPath = '/api/v9/channels/${SessionHarness.channelId}/messages';
const _otherSendPath =
    '/api/v9/channels/${SessionHarness.otherChannelId}/messages';
const _composer = ValueKey('message-composer');

void main() {
  testSession('a long rate limit says so at once and blocks no other channel', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _sendPath,
      (_) => jsonResponse({
        'message': 'You are being rate limited.',
        'retry_after': 7200.0,
      }, statusCode: 429),
    );
    session.transport.on(
      'POST',
      _otherSendPath,
      (_) => _sentMessage('elsewhere', SessionHarness.otherChannelId),
    );
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'hello');

    expect(
      find.text('Not sent. You are sending too fast. Try again in 2 hours.'),
      findsOneWidget,
    );
    expect(_boxText(tester), isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('channel-${SessionHarness.otherChannelId}')),
    );
    await session.settle();
    await _typeAndSend(tester, session, 'elsewhere');

    expect(
      _posted(session, _otherSendPath).single.json,
      containsPair('content', 'elsewhere'),
    );
  });

  testSession(
    'a message refused by a long rate limit never goes out by itself',
    (tester, session) async {
      session.transport.on(
        'POST',
        _sendPath,
        (_) => jsonResponse({'retry_after': 7200.0}, statusCode: 429),
      );
      await session.openChannel(SessionHarness.channelId);

      await _typeAndSend(tester, session, 'hello');
      await tester.pump(const Duration(hours: 3));
      await session.settle();

      expect(_posted(session, _sendPath), hasLength(1));
    },
  );

  testSession('an HTML rate limit page waits as the header says, then sends', (
    tester,
    session,
  ) async {
    final answers = [
      const DiscordHttpResponse(
        statusCode: 429,
        headers: {'retry-after': '2'},
        body: _htmlPage,
      ),
      _sentMessage('hello', SessionHarness.channelId),
    ];
    session.transport.on('POST', _sendPath, (_) => answers.removeAt(0));
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'hello');
    expect(_posted(session, _sendPath), hasLength(1));

    await tester.pump(const Duration(seconds: 2));
    await session.settle();

    _expectSameGuardedNonce(_posted(session, _sendPath), count: 2);
    expect(find.textContaining('Not sent'), findsNothing);
    expect(_boxText(tester), isEmpty);
  });

  testSession(
    'an HTML server error is repeated with the same nonce, then sends',
    (tester, session) async {
      final answers = [
        const DiscordHttpResponse(
          statusCode: 502,
          headers: {},
          body: _htmlPage,
        ),
        _sentMessage('hello', SessionHarness.channelId),
      ];
      session.transport.on('POST', _sendPath, (_) => answers.removeAt(0));
      await session.openChannel(SessionHarness.channelId);

      await _typeAndSend(tester, session, 'hello');
      await tester.pump(const Duration(seconds: 1));
      await session.settle();

      _expectSameGuardedNonce(_posted(session, _sendPath), count: 2);
      expect(find.textContaining('Not sent'), findsNothing);
      expect(_boxText(tester), isEmpty);
    },
  );

  testSession(
    'a server that keeps failing leaves the message failed, with why',
    (tester, session) async {
      session.transport.on(
        'POST',
        _sendPath,
        (_) => const DiscordHttpResponse(
          statusCode: 503,
          headers: {},
          body: _htmlPage,
        ),
      );
      await session.openChannel(SessionHarness.channelId);

      await _typeAndSend(tester, session, 'hello');
      await tester.pump(const Duration(seconds: 3));
      await session.settle();

      expect(_posted(session, _sendPath), hasLength(3));
      expect(
        find.text('Not sent. Discord is having trouble. Try again.'),
        findsOneWidget,
      );
      expect(_boxText(tester), isEmpty);
    },
  );

  testSession('a new message after a failure has a nonce of its own', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _sendPath,
      (_) => Future.error(Exception('the answer never came')),
    );
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'hello');
    await _typeAndSend(tester, session, 'hello again');

    final nonces = _posted(session, _sendPath).map(_nonce);
    expect(nonces.toSet(), hasLength(2));
  });

  testSession('the same words sent again after a success are a new message', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _sendPath,
      (_) => _sentMessage('ok', SessionHarness.channelId),
    );
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'ok');
    await _typeAndSend(tester, session, 'ok');

    final nonces = _posted(session, _sendPath).map(_nonce);
    expect(nonces.toSet(), hasLength(2));
  });
}

const _htmlPage = '<html><body><h1>Bad gateway</h1></body></html>';

Object? _nonce(RecordedRequest request) =>
    (request.json! as Map<String, Object?>)['nonce'];

/// Each request is the same message: one nonce, which Discord must enforce.
void _expectSameGuardedNonce(
  Iterable<RecordedRequest> requests, {
  required int count,
}) {
  expect(requests, hasLength(count));
  expect(requests.map(_nonce).toSet(), hasLength(1));
  expect(_nonce(requests.first), isNotNull);
  for (final request in requests) {
    expect(request.json, containsPair('enforce_nonce', true));
  }
}

Future<void> _typeAndSend(
  WidgetTester tester,
  SessionHarness session,
  String text,
) async {
  await tester.enterText(find.byKey(_composer), text);
  await session.settle();
  await tester.tap(find.byKey(const ValueKey('send-message')));
  await session.settle();
}

String _boxText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_composer)).controller!.text;

Iterable<RecordedRequest> _posted(SessionHarness session, String path) =>
    session.transport.requests.where(
      (request) => request.method == 'POST' && request.uri.path == path,
    );

DiscordHttpResponse _sentMessage(String content, String channelId) =>
    jsonResponse(
      rawMessage(
        id: '900000000000000001',
        channelId: channelId,
        guildId: SessionHarness.guildId,
        authorId: SessionHarness.currentUserId,
        content: content,
      ),
    );
