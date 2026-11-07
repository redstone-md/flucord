import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_rest_client.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _sendPath = '/api/v9/channels/${SessionHarness.channelId}/messages';
const _composer = ValueKey('message-composer');
const _sentId = '900000000000000001';

void main() {
  testSession('a sent message shows at once, then turns real on its echo', (
    tester,
    session,
  ) async {
    final answer = Completer<DiscordHttpResponse>();
    session.transport.on('POST', _sendPath, (_) => answer.future);
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'on its way');

    final nonce = _nonces(session).single;
    expect(_boxText(tester), isEmpty);
    expect(session.messageRow(nonce), findsOneWidget);
    expect(find.byKey(ValueKey('message-sending-$nonce')), findsOneWidget);

    await session.dispatch('MESSAGE_CREATE', {
      ..._ownMessage('on its way'),
      'nonce': nonce,
    });

    expect(session.messageRow(nonce), findsNothing);
    expect(session.messageRow(_sentId), findsOneWidget);
    expect(find.text('on its way'), findsOneWidget);
    answer.complete(jsonResponse(_ownMessage('on its way')));
    await session.settle();
    expect(find.text('on its way'), findsOneWidget);
  });

  testSession('a message with a file shows its upload as it goes', (
    tester,
    session,
  ) async {
    final folder = Directory.systemTemp.createTempSync('flucord-upload');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/proof.txt')..writeAsStringSync('proof');
    final answer = Completer<DiscordHttpResponse>();
    session.transport.on('POST', _sendPath, (_) => answer.future);
    await session.openChannel(SessionHarness.channelId);
    await _attachFile(tester, file);

    await _typeAndSend(tester, session, 'with a file');

    expect(find.text('proof.txt'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1.0,
    );
    answer.complete(jsonResponse(_ownMessage('with a file')));
    await session.settle();
    expect(find.text('100%'), findsNothing);
  });

  testSession('a failed send stays in place and says why', (
    tester,
    session,
  ) async {
    _refuseSend(session);
    await session.openChannel(SessionHarness.channelId);

    await _typeAndSend(tester, session, 'refused');

    final nonce = _nonces(session).single;
    expect(_boxText(tester), isEmpty);
    expect(session.messageRow(nonce), findsOneWidget);
    expect(
      find.text('Not sent. You do not have permission to send messages here.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('outgoing-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('outgoing-discard')), findsOneWidget);
  });

  testSession('Retry sends it again under the same nonce', (
    tester,
    session,
  ) async {
    _refuseSend(session);
    await session.openChannel(SessionHarness.channelId);
    await _typeAndSend(tester, session, 'again');
    session.transport.on(
      'POST',
      _sendPath,
      (_) => jsonResponse(_ownMessage('again')),
    );

    await tester.tap(find.byKey(const ValueKey('outgoing-retry')));
    await session.settle();

    final nonces = _nonces(session);
    expect(nonces, hasLength(2));
    expect(nonces.toSet(), hasLength(1));
    expect(session.messageRow(_sentId), findsOneWidget);
    expect(session.messageRow(nonces.first), findsNothing);
    expect(find.textContaining('Not sent'), findsNothing);
  });

  testSession('Delete takes the failed message away unsent', (
    tester,
    session,
  ) async {
    _refuseSend(session);
    await session.openChannel(SessionHarness.channelId);
    await _typeAndSend(tester, session, 'drop me');

    await tester.tap(find.byKey(const ValueKey('outgoing-discard')));
    await session.settle();

    expect(session.messageRow(_nonces(session).single), findsNothing);
    expect(find.text('drop me'), findsNothing);
    expect(_nonces(session), hasLength(1));
  });
}

void _refuseSend(SessionHarness session) => session.transport.on(
  'POST',
  _sendPath,
  (_) => jsonResponse({
    'code': 50013,
    'message': 'Missing Permissions',
  }, statusCode: 403),
);

Map<String, Object?> _ownMessage(String content) => rawMessage(
  id: _sentId,
  channelId: SessionHarness.channelId,
  guildId: SessionHarness.guildId,
  authorId: SessionHarness.currentUserId,
  content: content,
);

List<String> _nonces(SessionHarness session) => [
  for (final request in session.transport.requests)
    if (request.method == 'POST' && request.uri.path == _sendPath)
      (request.json! as Map<String, Object?>)['nonce']! as String,
];

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

Future<void> _attachFile(WidgetTester tester, File file) async {
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (_) async => [
      {'name': 'proof.txt', 'path': file.path, 'size': file.lengthSync()},
    ],
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  await tester.tap(find.byKey(const ValueKey('composer-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add-attachment')));
  await tester.pumpAndSettle();
}

String _boxText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_composer)).controller!.text;
