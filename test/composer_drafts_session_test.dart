import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/domain/discord_session.dart';

import 'support/fake_discord_wire.dart';
import 'support/fake_voice_message_recorder.dart';
import 'support/session_harness.dart';

const _sendPath = '/api/v9/channels/${SessionHarness.channelId}/messages';
const _otherSendPath =
    '/api/v9/channels/${SessionHarness.otherChannelId}/messages';
const _commandSearchPath =
    '/api/v9/channels/${SessionHarness.channelId}/application-commands/search';
const _replyTargetId = '900000000000000002';
const _composer = ValueKey('message-composer');
final _replyBar = find.textContaining('Replying to');
final _silentNotice = find.byKey(const ValueKey('composer-silent-notice'));

void main() {
  group('switching away and back', () {
    testSession('brings the text back', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _type(tester, session, 'half a thought');

      await session.openChannel(SessionHarness.otherChannelId);
      expect(_boxText(tester), isEmpty);

      await session.openChannel(SessionHarness.channelId);
      expect(_boxText(tester), 'half a thought');
    });

    testSession('brings the reply target back, and the reply still sends', (
      tester,
      session,
    ) async {
      session.transport.on('POST', _sendPath, (_) => _sentMessage('answer'));
      await session.openChannel(SessionHarness.channelId);
      await _startReply(tester, session);

      await session.openChannel(SessionHarness.otherChannelId);
      expect(_replyBar, findsNothing);

      await session.openChannel(SessionHarness.channelId);
      expect(_replyBar, findsOneWidget);

      await _typeAndSend(tester, session, 'answer');
      expect(
        _posted(session, _sendPath).single.json,
        containsPair(
          'message_reference',
          containsPair('message_id', _replyTargetId),
        ),
      );
    });

    testSession('brings the attachments back', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _attachFile(tester, session, 'notes.txt');

      await session.openChannel(SessionHarness.otherChannelId);
      expect(find.text('notes.txt'), findsNothing);

      await session.openChannel(SessionHarness.channelId);
      expect(find.text('notes.txt'), findsOneWidget);
    });

    testSession('brings back the silent setting of that message only', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _turnOnSilent(tester);

      await session.openChannel(SessionHarness.otherChannelId);
      expect(_silentNotice, findsNothing);

      await session.openChannel(SessionHarness.channelId);
      expect(_silentNotice, findsOneWidget);
    });

    testSession('does not tell Discord the user is typing', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _type(tester, session, 'half a thought');
      final typingBefore = _typingRequests(session);

      await session.openChannel(SessionHarness.otherChannelId);
      await session.openChannel(SessionHarness.channelId);

      expect(_typingRequests(session), typingBefore);
    });

    testSession('keeps a slash draft a command, not plain text', (
      tester,
      session,
    ) async {
      session.transport.on(
        'GET',
        _commandSearchPath,
        (_) => jsonResponse({
          'application_commands': [
            {
              'id': '700000000000000001',
              'application_id': '700000000000000002',
              'version': '700000000000000003',
              'name': 'ping',
              'description': 'Checks the bot',
              'type': 1,
            },
          ],
        }),
      );
      await session.openChannel(SessionHarness.channelId);
      await _type(tester, session, '/pi');
      await _waitForCommandList(tester, session);

      await session.openChannel(SessionHarness.otherChannelId);
      await session.openChannel(SessionHarness.channelId);
      await _waitForCommandList(tester, session);

      expect(find.text('/ping'), findsOneWidget);
    });

    testSession('brings back a half typed channel link', (
      tester,
      session,
    ) async {
      const suggestions = ValueKey('composer-autocomplete');
      await session.openChannel(SessionHarness.channelId);
      await _type(tester, session, 'see #gen');
      expect(find.byKey(suggestions), findsOneWidget);

      await session.openChannel(SessionHarness.otherChannelId);
      expect(find.byKey(suggestions), findsNothing);

      await session.openChannel(SessionHarness.channelId);
      expect(_boxText(tester), 'see #gen');
      expect(find.byKey(suggestions), findsNothing);
    });
  });

  testSession(
    'a channel with no composer does not lose the draft',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _startReply(tester, session);
      await _type(tester, session, 'see #gen');

      await session.openChannel(SessionHarness.otherChannelId);
      expect(find.byKey(_composer), findsNothing);

      await session.openChannel(SessionHarness.channelId);
      expect(_boxText(tester), 'see #gen');
      expect(_replyBar, findsOneWidget);
    },
    ready: _readyWithReadOnlyOtherChannel(),
  );

  testSession('two channels hold different drafts at the same time', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await _type(tester, session, 'for general');
    await _attachFile(tester, session, 'general.txt');

    await session.openChannel(SessionHarness.otherChannelId);
    await _type(tester, session, 'for random');
    await _attachFile(tester, session, 'random.txt');

    await session.openChannel(SessionHarness.channelId);
    expect(_boxText(tester), 'for general');
    expect(find.text('general.txt'), findsOneWidget);
    expect(find.text('random.txt'), findsNothing);

    await session.openChannel(SessionHarness.otherChannelId);
    expect(_boxText(tester), 'for random');
    expect(find.text('random.txt'), findsOneWidget);
    expect(find.text('general.txt'), findsNothing);
  });

  group('a successful send', () {
    testSession('clears only the draft of its own channel', (
      tester,
      session,
    ) async {
      session.transport.on(
        'POST',
        _otherSendPath,
        (_) => _sentMessage('sent', channelId: SessionHarness.otherChannelId),
      );
      await session.openChannel(SessionHarness.channelId);
      await _startReply(tester, session);
      await _type(tester, session, 'kept');

      await session.openChannel(SessionHarness.otherChannelId);
      await _typeAndSend(tester, session, 'sent');
      expect(_boxText(tester), isEmpty);

      await session.openChannel(SessionHarness.channelId);
      expect(_boxText(tester), 'kept');
      expect(_replyBar, findsOneWidget);

      await session.openChannel(SessionHarness.otherChannelId);
      expect(_boxText(tester), isEmpty);
      expect(_replyBar, findsNothing);
    });

    testSession('that finishes after a switch clears its reply target', (
      tester,
      session,
    ) async {
      final answer = _holdSend(session);
      await session.openChannel(SessionHarness.channelId);
      await _startReply(tester, session);
      await _typeAndSend(tester, session, 'answer');
      await session.openChannel(SessionHarness.otherChannelId);

      answer.complete(_sentMessage('answer'));
      await session.settle();
      await session.openChannel(SessionHarness.channelId);

      expect(_boxText(tester), isEmpty);
      expect(_replyBar, findsNothing);
    });

    testSession('leaves the reply target of a later draft in that channel', (
      tester,
      session,
    ) async {
      final answer = _holdSend(session);
      await session.openChannel(SessionHarness.channelId);
      await _typeAndSend(tester, session, 'plain');
      await _startReply(tester, session);
      await session.openChannel(SessionHarness.otherChannelId);

      answer.complete(_sentMessage('plain'));
      await session.settle();
      await session.openChannel(SessionHarness.channelId);

      expect(_replyBar, findsOneWidget);
    });
  });

  group('a send that fails after a switch', () {
    testSession('returns to the draft of its own channel, whole', (
      tester,
      session,
    ) async {
      final answer = _holdSend(session);
      await session.openChannel(SessionHarness.channelId);
      await _startReply(tester, session);
      await _attachFile(tester, session, 'notes.txt');
      await _turnOnSilent(tester);
      await _typeAndSend(tester, session, 'answer');
      await session.openChannel(SessionHarness.otherChannelId);
      await _type(tester, session, 'for random');

      answer.complete(_refusal());
      await session.settle();

      expect(_boxText(tester), 'for random');
      expect(find.textContaining('did not send'), findsOneWidget);

      await session.openChannel(SessionHarness.channelId);
      expect(_boxText(tester), 'answer');
      expect(find.text('notes.txt'), findsOneWidget);
      expect(_replyBar, findsOneWidget);
      expect(_silentNotice, findsOneWidget);
    });

    testSession('does not overwrite text typed after it', (
      tester,
      session,
    ) async {
      final answer = _holdSend(session);
      await session.openChannel(SessionHarness.channelId);
      await _typeAndSend(tester, session, 'first');
      await _type(tester, session, 'second');
      await session.openChannel(SessionHarness.otherChannelId);

      answer.complete(_refusal());
      await session.settle();
      await session.openChannel(SessionHarness.channelId);

      expect(_boxText(tester), 'second');
    });

    testSession(
      'returns to the draft when no composer is open',
      (tester, session) async {
        final answer = _holdSend(session);
        await session.openChannel(SessionHarness.channelId);
        await _typeAndSend(tester, session, 'first');
        await session.openChannel(SessionHarness.otherChannelId);
        expect(find.byKey(_composer), findsNothing);

        answer.complete(_refusal());
        await session.settle();
        await session.openChannel(SessionHarness.channelId);

        expect(_boxText(tester), 'first');
      },
      ready: _readyWithReadOnlyOtherChannel(),
    );
  });

  group('a voice recording in progress', () {
    final recorder = FakeVoiceMessageRecorder();

    testSession(
      'is discarded on a switch, and other drafts stay',
      (tester, session) async {
        await session.openChannel(SessionHarness.otherChannelId);
        await _type(tester, session, 'for random');
        await session.openChannel(SessionHarness.channelId);
        await tester.tap(find.byKey(const ValueKey('record-voice-message')));
        await session.settle();
        expect(recorder.isRecording, isTrue);
        expect(find.byKey(_composer), findsNothing);

        await session.openChannel(SessionHarness.otherChannelId);
        expect(recorder.isRecording, isFalse);
        expect(recorder.cancelCount, 1);
        expect(_boxText(tester), 'for random');

        await session.openChannel(SessionHarness.channelId);
        expect(recorder.isRecording, isFalse);
        expect(_boxText(tester), isEmpty);
      },
      voiceMessageRecorder: recorder,
    );
  });

  testSession('a draft does not reach the next sign-in', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await _startReply(tester, session);
    await _type(tester, session, 'private words');

    await session.signOut();
    session.remoteAuth.add(
      DiscordRemoteAuthCompleted(
        DiscordDesktopUserSession(
          SessionHarness.tokenOf(SessionHarness.currentUserId),
        ),
      ),
    );
    await session.connectToReady(SessionHarness.defaultReady());
    // The Connections dialog stays open through a sign-in, in front of the app.
    await tester.tap(find.byTooltip('Close'));
    await session.settle();
    await session.openChannel(SessionHarness.channelId);

    expect(_boxText(tester), isEmpty);
    expect(_replyBar, findsNothing);
  });
}

Map<String, Object?>
_readyWithReadOnlyOtherChannel() => SessionHarness.defaultReady()
  ..['users'] = [
    {'id': SessionHarness.currentUserId, 'username': 'me'},
    {'id': SessionHarness.friendId, 'username': 'friend'},
  ]
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
        rawChannel(id: SessionHarness.channelId, name: 'general'),
        {
          ...rawChannel(id: SessionHarness.otherChannelId, name: 'rules'),
          'permission_overwrites': [
            {
              'id': SessionHarness.guildId,
              'type': 0,
              'allow': '0',
              'deny': '${DiscordPermissions.sendMessages}',
            },
          ],
        },
      ],
      everyonePermissions:
          '${DiscordPermissions.viewChannel | DiscordPermissions.sendMessages | DiscordPermissions.readMessageHistory | DiscordPermissions.attachFiles}',
    ),
  ];

Future<void> _type(
  WidgetTester tester,
  SessionHarness session,
  String text,
) async {
  await tester.enterText(find.byKey(_composer), text);
  await session.settle();
}

Future<void> _typeAndSend(
  WidgetTester tester,
  SessionHarness session,
  String text,
) async {
  await _type(tester, session, text);
  await tester.tap(find.byKey(const ValueKey('send-message')));
  await session.settle();
}

/// Past the debounce the command list waits for before it asks Discord.
Future<void> _waitForCommandList(
  WidgetTester tester,
  SessionHarness session,
) async {
  await tester.pump(const Duration(milliseconds: 250));
  await session.settle();
}

/// A message arrives in the open channel, and the user picks Reply on it.
Future<void> _startReply(WidgetTester tester, SessionHarness session) async {
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
      id: _replyTargetId,
      channelId: SessionHarness.channelId,
      guildId: SessionHarness.guildId,
      authorId: SessionHarness.friendId,
      content: 'answer me',
    ),
  );
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(session.messageRow(_replyTargetId)));
  await session.settle();
  await tester.tap(find.byTooltip('Reply'));
  await session.settle();
  await mouse.moveTo(Offset.zero);
  await session.settle();
}

/// Picks one file through the composer's menu. The native dialog answers on the
/// file picker's platform channel, which is the only part faked here.
Future<void> _attachFile(
  WidgetTester tester,
  SessionHarness session,
  String name,
) async {
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (_) async => [
      {'name': name, 'path': '/tmp/$name', 'size': 5},
    ],
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  await tester.tap(find.byKey(const ValueKey('composer-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add-attachment')));
  await tester.pumpAndSettle();
}

Future<void> _turnOnSilent(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('composer-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('send-silently')));
  await tester.pumpAndSettle();
}

Completer<DiscordHttpResponse> _holdSend(SessionHarness session) {
  final answer = Completer<DiscordHttpResponse>();
  session.transport.on('POST', _sendPath, (_) => answer.future);
  return answer;
}

DiscordHttpResponse _refusal() =>
    jsonResponse({'message': 'Missing Permissions'}, statusCode: 403);

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

String _boxText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_composer)).controller!.text;

Iterable<RecordedRequest> _posted(SessionHarness session, String path) =>
    session.transport.requests.where(
      (request) => request.method == 'POST' && request.uri.path == path,
    );

int _typingRequests(SessionHarness session) => session.transport.requests
    .where((request) => request.uri.path.endsWith('/typing'))
    .length;
