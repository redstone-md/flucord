import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_frecency_proto.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/expression_favorites.dart';

import 'support/fake_discord_wire.dart';
import 'support/fake_voice_message_recorder.dart';
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

  group('a send that finishes after a channel switch', () {
    Future<Completer<DiscordHttpResponse>> sendThenSwitch(
      WidgetTester tester,
      SessionHarness session,
    ) async {
      final answer = _holdSend(session, _sendPath);
      await session.openChannel(SessionHarness.channelId);
      await _typeAndSend(tester, session, 'first');
      await session.openChannel(SessionHarness.otherChannelId);
      await tester.enterText(find.byKey(_composer), 'draft here');
      await session.settle();
      return answer;
    }

    testSession('leaves the new box alone when it succeeds', (
      tester,
      session,
    ) async {
      final answer = await sendThenSwitch(tester, session);

      answer.complete(_sentMessage('first'));
      await session.settle();

      expect(_boxText(tester), 'draft here');
    });

    testSession(
      'leaves the new box alone when it fails, and names the channel',
      (tester, session) async {
        final answer = await sendThenSwitch(tester, session);

        answer.complete(_refusal('Missing Permissions'));
        await session.settle();

        expect(_boxText(tester), 'draft here');
        expect(
          find.text(
            'Your message to #general did not send. Missing Permissions',
          ),
          findsOneWidget,
        );
      },
    );

    testSession('lets the new channel send while the first is held', (
      tester,
      session,
    ) async {
      const otherPath =
          '/api/v9/channels/${SessionHarness.otherChannelId}/messages';
      final answer = await sendThenSwitch(tester, session);
      session.transport.on(
        'POST',
        otherPath,
        (_) => _sentMessage('here', channelId: SessionHarness.otherChannelId),
      );

      await tester.tap(find.byKey(const ValueKey('send-message')));
      await session.settle();

      expect(
        _posted(session, otherPath).single.json,
        containsPair('content', 'draft here'),
      );
      expect(_boxText(tester), isEmpty);
      answer.complete(_sentMessage('first'));
      await session.settle();
    });

    testSession('keeps a reply started in the new channel', (
      tester,
      session,
    ) async {
      final answer = await sendThenSwitch(tester, session);
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: '900000000000000002',
          channelId: SessionHarness.otherChannelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.friendId,
          content: 'answer me',
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(session.messageRow('900000000000000002')),
      );
      await session.settle();
      await tester.tap(find.byTooltip('Reply'));
      await session.settle();
      expect(find.textContaining('Replying to'), findsOneWidget);

      answer.complete(_sentMessage('first'));
      await session.settle();

      expect(find.textContaining('Replying to'), findsOneWidget);
    });
  });

  group('slowmode', () {
    Finder sendButton() => find.byKey(const ValueKey('send-message'));
    bool sendEnabled(WidgetTester tester) =>
        tester.widget<IconButton>(sendButton()).onPressed != null;

    testSession('blocks the button and Enter until the time ends', (
      tester,
      session,
    ) async {
      session.transport.on('POST', _sendPath, (_) => _sentMessage('first'));
      await session.openChannel(SessionHarness.channelId);

      await _typeAndSend(tester, session, 'first');
      await tester.enterText(find.byKey(_composer), 'second');
      await session.settle();

      expect(sendEnabled(tester), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await session.settle();
      expect(_posted(session, _sendPath), hasLength(1));
      expect(_boxText(tester), 'second');
    }, ready: _slowmodeReady());

    testSession(
      'lets the next send go once the time has ended',
      (tester, session) async {
        session.transport.on('POST', _sendPath, (_) => _sentMessage('first'));
        await session.openChannel(SessionHarness.channelId);

        await _typeAndSend(tester, session, 'first');
        await tester.enterText(find.byKey(_composer), 'second');
        await session.settle();
        expect(sendEnabled(tester), isFalse);

        // The composer reads the wall clock, so real time has to pass here. The
        // fake pump then fires its one second tick.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1100)),
        );
        await tester.pump(const Duration(seconds: 1));

        expect(sendEnabled(tester), isTrue);
        expect(
          find.byKey(const ValueKey('composer-slowmode-countdown')),
          findsNothing,
        );
      },
      ready: _slowmodeReady(seconds: 1),
    );

    testSession('still holds after switching away and back', (
      tester,
      session,
    ) async {
      session.transport.on('POST', _sendPath, (_) => _sentMessage('first'));
      await session.openChannel(SessionHarness.channelId);
      await _typeAndSend(tester, session, 'first');

      await session.openChannel(SessionHarness.otherChannelId);
      await session.openChannel(SessionHarness.channelId);
      await tester.enterText(find.byKey(_composer), 'second');
      await session.settle();

      expect(sendEnabled(tester), isFalse);
      expect(
        find.byKey(const ValueKey('composer-slowmode-countdown')),
        findsOneWidget,
      );
    }, ready: _slowmodeReady());

    testSession('starts only in the channel the send went to', (
      tester,
      session,
    ) async {
      final answer = _holdSend(session, _sendPath);
      await session.openChannel(SessionHarness.channelId);
      await _typeAndSend(tester, session, 'first');
      await session.openChannel(SessionHarness.otherChannelId);

      answer.complete(_sentMessage('first'));
      await session.settle();
      await tester.enterText(find.byKey(_composer), 'second');
      await session.settle();

      expect(sendEnabled(tester), isTrue);
    }, ready: _slowmodeReady());

    testSession('does not start when the send failed', (tester, session) async {
      _refuseSend(session, 'Missing Permissions');
      await session.openChannel(SessionHarness.channelId);

      await _typeAndSend(tester, session, 'first');

      expect(sendEnabled(tester), isTrue);
    }, ready: _slowmodeReady());

    testSession(
      'does not hold a member who may manage messages',
      (tester, session) async {
        session.transport.on('POST', _sendPath, (_) => _sentMessage('first'));
        await session.openChannel(SessionHarness.channelId);

        await _typeAndSend(tester, session, 'first');
        await tester.enterText(find.byKey(_composer), 'second');
        await session.settle();

        expect(sendEnabled(tester), isTrue);
        expect(
          find.byKey(const ValueKey('composer-slowmode-countdown')),
          findsNothing,
        );
      },
      ready: _slowmodeReady(
        extraPermissions: DiscordPermissions.manageMessages,
      ),
    );

    testSession(
      'blocks a voice message too',
      (tester, session) async {
        session.transport.on('POST', _sendPath, (_) => _sentMessage('first'));
        await session.openChannel(SessionHarness.channelId);
        await _typeAndSend(tester, session, 'first');

        final record = tester.widget<IconButton>(
          find.byKey(const ValueKey('record-voice-message')),
        );
        expect(record.onPressed, isNull);
      },
      ready: _slowmodeReady(),
      voiceMessageRecorder: FakeVoiceMessageRecorder(),
    );

    testSession('blocks a poll too', (tester, session) async {
      session.transport.on('POST', _sendPath, (_) => _sentMessage('first'));
      await session.openChannel(SessionHarness.channelId);
      await _typeAndSend(tester, session, 'first');

      await tester.tap(find.byKey(const ValueKey('composer-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-poll')));
      await tester.pumpAndSettle();

      expect(find.text('Create a poll'), findsNothing);
    }, ready: _slowmodeReady());

    const gifUrl = 'https://tenor.example/starred';
    testSession(
      'blocks a GIF too',
      (tester, session) async {
        session.transport.on('POST', _sendPath, (_) => _sentMessage('first'));
        await session.openChannel(SessionHarness.channelId);
        await _typeAndSend(tester, session, 'first');

        await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
        await session.settle();
        await tester.tap(find.byKey(const ValueKey('gif-favorite-$gifUrl')));
        await session.settle();

        expect(_posted(session, _sendPath), hasLength(1));
      },
      ready: _slowmodeReady(),
      routes: (transport) => transport.on(
        'GET',
        '/api/v9/users/@me/settings-proto/2',
        (_) => jsonResponse({
          'settings': base64.encode(
            DiscordFrecencyProtoCodec.apply(
              ProtoMessage(),
              const ExpressionFavorites(
                gifs: [FavoriteGif(url: gifUrl, src: gifUrl)],
              ),
            ).encode(),
          ),
        }),
      ),
    );
  });
}

/// A server whose two channels both have slowmode. The account's member record
/// is there because without one the client cannot judge permissions and allows
/// everything, slowmode included.
Map<String, Object?> _slowmodeReady({
  int seconds = 30,
  BigInt? extraPermissions,
}) {
  Map<String, Object?> slow(String id, String name) => {
    ...rawChannel(id: id, name: name),
    'rate_limit_per_user': seconds,
  };
  final everyone =
      DiscordPermissions.viewChannel |
      DiscordPermissions.sendMessages |
      DiscordPermissions.readMessageHistory |
      (extraPermissions ?? BigInt.zero);
  return SessionHarness.defaultReady()
    ..['users'] = [
      {'id': SessionHarness.currentUserId, 'username': 'me'},
    ]
    ..['private_channels'] = <Object?>[]
    ..['merged_members'] = [
      [
        {'user_id': SessionHarness.currentUserId, 'roles': <String>[]},
      ],
    ]
    ..['guilds'] = [
      rawGuild(
        id: SessionHarness.guildId,
        name: 'The Forge',
        channels: [
          slow(SessionHarness.channelId, 'general'),
          slow(SessionHarness.otherChannelId, 'random'),
        ],
        everyonePermissions: '$everyone',
      ),
    ];
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
