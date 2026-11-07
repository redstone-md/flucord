import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/chat_models.dart';

import 'support/fake_discord_wire.dart';
import 'support/fake_voice_message_recorder.dart';
import 'support/session_harness.dart';

const _uploadHost = 'discord-attachments-uploads-prd.storage.googleapis.com';
const _uploadPath = '/upload-slot/voice-message.ogg';
const _uploadedFilename = 'upload-slot/voice-message.ogg';
const _audio = [79, 103, 103, 83, 1, 2, 3, 4];

void main() {
  final folder = Directory.systemTemp.createTempSync('flucord-voice-session-');
  tearDownAll(() => folder.deleteSync(recursive: true));
  final file = File('${folder.path}${Platform.pathSeparator}voice.ogg')
    ..writeAsBytesSync(_audio);
  PendingVoiceMessage recording() => PendingVoiceMessage(
    name: 'voice-message.ogg',
    path: file.path,
    size: _audio.length,
    durationSecs: 2.5,
    waveform: 'AQID',
  );

  for (final (place, channelId, space) in [
    ('a server channel', SessionHarness.channelId, SessionHarness.guildId),
    ('a DM', SessionHarness.dmChannelId, 'direct-messages'),
  ]) {
    testSession(
      'a voice message in $place goes out through an upload slot',
      (tester, session) async {
        _routeUpload(session, channelId);
        await session.openChannel(channelId, space: space);

        await _recordAndSend(tester, session);

        final requests = session.transport.requests;
        final slot = requests.singleWhere(
          (r) => r.uri.path == '/api/v9/channels/$channelId/attachments',
        );
        expect(slot.method, 'POST');
        expect(slot.json, {
          'files': [
            {'id': '0', 'filename': 'voice-message.ogg', 'file_size': 8},
          ],
        });

        final upload = requests.singleWhere((r) => r.uri.host == _uploadHost);
        expect(upload.method, 'PUT');
        expect(upload.body, _audio);
        expect(upload.headers['content-type'], 'audio/ogg');
        expect(
          upload.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );

        final post = requests.singleWhere(
          (r) =>
              r.method == 'POST' &&
              r.uri.path == '/api/v9/channels/$channelId/messages',
        );
        expect(requests.indexOf(slot), lessThan(requests.indexOf(upload)));
        expect(requests.indexOf(upload), lessThan(requests.indexOf(post)));
        final body = post.json! as Map<String, Object?>;
        expect(body['flags'], 8192);
        expect(body['attachments'], [
          {
            'id': 0,
            'filename': 'voice-message.ogg',
            'uploaded_filename': _uploadedFilename,
            'duration_secs': 2.5,
            'waveform': 'AQID',
          },
        ]);

        expect(
          find.descendant(
            of: session.messageRow('900000000000000001'),
            matching: find.byKey(
              const ValueKey('attachment-audio-900000000000000002'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('record-voice-message')),
          findsOneWidget,
        );
      },
      voiceMessageRecorder: FakeVoiceMessageRecorder(pending: recording()),
    );
  }

  final sending = FakeVoiceMessageRecorder(pending: recording());
  testSession(
    'a voice message shows at once as sending, then turns real on its echo',
    (tester, session) async {
      final answer = Completer<DiscordHttpResponse>();
      final uploaded = Completer<void>();
      _routeUpload(session, SessionHarness.channelId);
      session.transport
        ..on('POST', _sendPath, (_) => answer.future)
        ..holdBodyHalfway('PUT', _uploadPath, uploaded.future);
      await session.openChannel(SessionHarness.channelId);

      await _recordAndSend(tester, session);

      expect(find.text('50%'), findsOneWidget);
      uploaded.complete();
      await session.settle();

      final nonce = _nonces(session).single;
      final row = session.messageRow(nonce);
      expect(row, findsOneWidget);
      expect(find.byKey(ValueKey('message-sending-$nonce')), findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(ValueKey('attachment-audio-$nonce-voice')),
        ),
        findsOneWidget,
      );
      // The file is up, but the message post is still on its way.
      expect(
        find.descendant(of: row, matching: find.text('99%')),
        findsOneWidget,
      );
      expect(find.text('100%'), findsNothing);
      expect(
        find.descendant(of: row, matching: find.text('Voice message')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('record-voice-message')),
        findsOneWidget,
      );

      await session.dispatch('MESSAGE_CREATE', {
        ..._voiceMessage(SessionHarness.channelId),
        'nonce': nonce,
      });

      expect(session.messageRow(nonce), findsNothing);
      expect(session.messageRow(_sentId), findsOneWidget);
      expect(sending.deleted, [same(sending.pending)]);
      answer.complete(jsonResponse(_voiceMessage(SessionHarness.channelId)));
      await session.settle();
      expect(session.messageRow(_sentId), findsOneWidget);
      expect(find.text('100%'), findsNothing);
    },
    voiceMessageRecorder: sending,
  );

  final failing = FakeVoiceMessageRecorder(pending: recording());
  testSession(
    'a failed voice message stays in place and says why',
    (tester, session) async {
      _routeUpload(session, SessionHarness.channelId);
      _refuse(session, _slotPath);
      await session.openChannel(SessionHarness.channelId);

      await _recordAndSend(tester, session);

      final row = session.messageRow(_outgoingNonce(tester));
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            'Not sent. You do not have permission to send messages here.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('outgoing-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('outgoing-discard')), findsOneWidget);
      expect(failing.deleted, isEmpty);
    },
    voiceMessageRecorder: failing,
  );

  final retried = FakeVoiceMessageRecorder(pending: recording());
  testSession(
    'Retry sends a failed voice message again under the same nonce',
    (tester, session) async {
      _routeUpload(session, SessionHarness.channelId);
      _refuse(session, _sendPath);
      await session.openChannel(SessionHarness.channelId);
      await _recordAndSend(tester, session);
      expect(find.byKey(const ValueKey('outgoing-retry')), findsOneWidget);
      _routeUpload(session, SessionHarness.channelId);

      await tester.tap(find.byKey(const ValueKey('outgoing-retry')));
      await session.settle();

      final nonces = _nonces(session);
      expect(nonces, hasLength(2));
      expect(nonces.toSet(), hasLength(1));
      expect(session.messageRow(nonces.first), findsNothing);
      expect(session.messageRow(_sentId), findsOneWidget);
      expect(find.textContaining('Not sent'), findsNothing);
      expect(retried.deleted, [same(retried.pending)]);
    },
    voiceMessageRecorder: retried,
  );

  final discarded = FakeVoiceMessageRecorder(pending: recording());
  testSession(
    'Delete drops a failed voice message and its recording',
    (tester, session) async {
      _routeUpload(session, SessionHarness.channelId);
      _refuse(session, _slotPath);
      await session.openChannel(SessionHarness.channelId);
      await _recordAndSend(tester, session);
      final nonce = _outgoingNonce(tester);

      await tester.tap(find.byKey(const ValueKey('outgoing-discard')));
      await session.settle();

      expect(session.messageRow(nonce), findsNothing);
      expect(find.textContaining('Not sent'), findsNothing);
      expect(discarded.deleted, [same(discarded.pending)]);
      expect(
        session.transport.requests.where((r) => r.uri.path == _slotPath),
        hasLength(1),
      );
    },
    voiceMessageRecorder: discarded,
  );

  final signedOut = FakeVoiceMessageRecorder(pending: recording());
  testSession(
    'signing out lets go of a failed voice message and its recording',
    (tester, session) async {
      _routeUpload(session, SessionHarness.channelId);
      _refuse(session, _slotPath);
      await session.openChannel(SessionHarness.channelId);
      await _recordAndSend(tester, session);
      expect(signedOut.deleted, isEmpty);

      await session.signOut();

      expect(signedOut.deleted, [same(signedOut.pending)]);
    },
    voiceMessageRecorder: signedOut,
  );

  testSession(
    'a channel without the voice message permission offers no microphone',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      expect(find.byKey(const ValueKey('record-voice-message')), findsNothing);
    },
    ready: _readyWithoutVoiceMessages(),
    voiceMessageRecorder: FakeVoiceMessageRecorder(),
  );
}

/// The default READY, with an `@everyone` that may send messages and files
/// but not voice messages. The account's member record makes the role count.
Map<String, Object?> _readyWithoutVoiceMessages() {
  final ready = SessionHarness.defaultReady()
    ..['merged_members'] = [
      [
        {'user_id': SessionHarness.currentUserId, 'roles': <String>[]},
      ],
    ];
  final guild = (ready['guilds']! as List).single as Map<String, Object?>;
  final everyone = (guild['roles']! as List).single as Map<String, Object?>;
  final permissions = BigInt.parse(everyone['permissions']! as String);
  everyone['permissions'] =
      '${permissions & ~DiscordPermissions.sendVoiceMessages}';
  return ready;
}

const _sentId = '900000000000000001';
const _sendPath = '/api/v9/channels/${SessionHarness.channelId}/messages';
const _slotPath = '/api/v9/channels/${SessionHarness.channelId}/attachments';

/// The nonces the voice message posts went out with, in order.
List<String> _nonces(SessionHarness session) => [
  for (final request in session.transport.requests)
    if (request.method == 'POST' && request.uri.path == _sendPath)
      (request.json! as Map<String, Object?>)['nonce']! as String,
];

/// The nonce of the one failed message on screen, read from its row's key.
/// A refused upload slot never reaches the post that carries the nonce.
String _outgoingNonce(WidgetTester tester) {
  final key =
      tester
              .widgetList(
                find.byWidgetPredicate(
                  (widget) =>
                      widget.key is ValueKey<String> &&
                      (widget.key! as ValueKey<String>).value.startsWith(
                        'outgoing-failed-',
                      ),
                ),
              )
              .single
              .key!
          as ValueKey<String>;
  return key.value.substring('outgoing-failed-'.length);
}

void _refuse(SessionHarness session, String path) => session.transport.on(
  'POST',
  path,
  (_) => jsonResponse({
    'code': 50013,
    'message': 'Missing Permissions',
  }, statusCode: 403),
);

/// Discord's three answers: the upload slot, the storage bucket's empty 200,
/// and the posted voice message.
void _routeUpload(SessionHarness session, String channelId) {
  session.transport
    ..on(
      'POST',
      '/api/v9/channels/$channelId/attachments',
      (_) => jsonResponse({
        'attachments': [
          {
            'id': 0,
            'upload_url': 'https://$_uploadHost$_uploadPath?upload_id=abc',
            'upload_filename': _uploadedFilename,
          },
        ],
      }),
    )
    ..on('PUT', _uploadPath, (_) => jsonResponse(null))
    ..on(
      'POST',
      '/api/v9/channels/$channelId/messages',
      (_) => jsonResponse(_voiceMessage(channelId)),
    );
}

Map<String, Object?> _voiceMessage(String channelId) => {
  ...rawMessage(
    id: '900000000000000001',
    channelId: channelId,
    authorId: SessionHarness.currentUserId,
    content: '',
  ),
  'flags': 8192,
  'attachments': [
    {
      'id': '900000000000000002',
      'filename': 'voice-message.ogg',
      'size': 8,
      'url': 'https://cdn.discordapp.com/attachments/1/2/voice-message.ogg',
      'proxy_url':
          'https://media.discordapp.net/attachments/1/2/voice-message.ogg',
      'content_type': 'audio/ogg',
      'duration_secs': 2.5,
      'waveform': 'AQID',
    },
  ],
};

Future<void> _recordAndSend(WidgetTester tester, SessionHarness session) async {
  await tester.tap(find.byKey(const ValueKey('record-voice-message')));
  await session.settle();
  await tester.tap(find.byKey(const ValueKey('send-voice-message')));
  await session.settle();
}
