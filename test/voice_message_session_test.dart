import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app_log.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/voice_message_recorder.dart';

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

  final failing = FakeVoiceMessageRecorder(pending: recording());
  testSession(
    'a failed voice message is logged with its cause and can be retried',
    (tester, session) async {
      final log = <String>[];
      AppLog.redirect = (level, scope, message, error) =>
          log.add('$scope $message :: $error');
      addTearDown(() => AppLog.redirect = null);
      _routeUpload(session, SessionHarness.channelId);
      session.transport.on(
        'POST',
        '/api/v9/channels/${SessionHarness.channelId}/attachments',
        (_) =>
            jsonResponse({'message': 'Upload slots are down'}, statusCode: 500),
      );
      await session.openChannel(SessionHarness.channelId);

      await _recordAndSend(tester, session);

      expect(
        log,
        contains(
          allOf(contains('voice message'), contains('Upload slots are down')),
        ),
      );
      expect(failing.deleted, isEmpty);
      expect(find.byKey(const ValueKey('retry-voice-message')), findsOneWidget);

      _routeUpload(session, SessionHarness.channelId);
      await tester.tap(find.byKey(const ValueKey('retry-voice-message')));
      await session.settle();

      expect(session.messageRow('900000000000000001'), findsOneWidget);
      expect(failing.deleted, [same(failing.pending)]);
    },
    voiceMessageRecorder: failing,
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
