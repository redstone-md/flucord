import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_rest_client.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _sendPath = '/api/v9/channels/${SessionHarness.channelId}/messages';
const _composer = ValueKey('message-composer');

void main() {
  testSession('text typed while a send runs stays when the send finishes', (
    tester,
    session,
  ) async {
    final answer = _holdSend(session, _sendPath);
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'first');
    expect(_boxText(tester), isEmpty);

    await tester.enterText(find.byKey(_composer), 'second');
    await session.settle();
    answer.complete(_sentMessage('first'));
    await session.settle();

    expect(_boxText(tester), 'second');
    expect(
      _posted(session, _sendPath).single.json,
      containsPair('content', 'first'),
    );
  });

  testSession('a failed send brings the text back and says why', (
    tester,
    session,
  ) async {
    _refuseSend(session, 'Missing Permissions');
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'hello');

    expect(_boxText(tester), 'hello');
    expect(
      find.text('Your message to #general did not send. Missing Permissions'),
      findsOneWidget,
    );
  });

  testSession('a send that fails with no answer still says it did not go out', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _sendPath,
      (_) => Future.error(Exception('connection reset')),
    );
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'hello');

    expect(_boxText(tester), 'hello');
    expect(
      find.text('Your message to #general did not send. Try again.'),
      findsOneWidget,
    );
  });

  testSession('a failed send can be sent again as it was, silent flag too', (
    tester,
    session,
  ) async {
    _refuseSend(session, 'Missing Permissions');
    await session.openChannel(SessionHarness.channelId);
    await tester.tap(find.byKey(const ValueKey('composer-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-silently')));
    await tester.pumpAndSettle();
    await _typeAndSend(tester, session, 'quiet');
    expect(
      find.byKey(const ValueKey('composer-silent-notice')),
      findsOneWidget,
    );

    session.transport.on('POST', _sendPath, (_) => _sentMessage('quiet'));
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await session.settle();

    expect(_boxText(tester), isEmpty);
    final sends = _posted(session, _sendPath);
    expect(sends, hasLength(2));
    expect(sends.last.json, containsPair('content', 'quiet'));
    expect(sends.last.json, containsPair('flags', 4096));
  });

  testSession('a failed send does not overwrite text typed after it', (
    tester,
    session,
  ) async {
    final answer = _holdSend(session, _sendPath);
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'first');
    await tester.enterText(find.byKey(_composer), 'second');
    await session.settle();
    answer.complete(_refusal('Missing Permissions'));
    await session.settle();

    expect(_boxText(tester), 'second');
    expect(find.textContaining('did not send'), findsOneWidget);
  });
}

void _refuseSend(SessionHarness session, String reason) =>
    session.transport.on('POST', _sendPath, (_) => _refusal(reason));

DiscordHttpResponse _refusal(String reason) =>
    jsonResponse({'code': 50013, 'message': reason}, statusCode: 403);

Completer<DiscordHttpResponse> _holdSend(SessionHarness session, String path) {
  final answer = Completer<DiscordHttpResponse>();
  session.transport.on('POST', path, (_) => answer.future);
  return answer;
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

DiscordHttpResponse _sentMessage(
  String content, {
  String channelId = SessionHarness.channelId,
}) => jsonResponse(
  rawMessage(
    id: '900000000000000001',
    channelId: channelId,
    guildId: SessionHarness.guildId,
    authorId: SessionHarness.currentUserId,
    content: content,
  ),
);
