import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/composer_draft.dart';
import 'package:flucord/src/domain/voice_message_recorder.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/build_counter.dart';
import 'support/fake_voice_message_recorder.dart';

void main() {
  testWidgets('records and uploads a voice message from an empty composer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recorder = FakeVoiceMessageRecorder();
    addTearDown(recorder.dispose);
    PendingVoiceMessage? sent;
    void Function()? release;

    await tester.pumpWidget(
      _composerApp(
        recorder: recorder,
        onSendVoiceMessage: (message, releaseFile) {
          sent = message;
          release = releaseFile;
        },
      ),
    );

    expect(find.byKey(const ValueKey('record-voice-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-message')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('record-voice-message')));
    await tester.pump();
    recorder.emit(
      const VoiceMessageRecordingProgress(
        duration: Duration(milliseconds: 1240),
        level: 0.8,
      ),
    );
    await tester.pump();

    expect(recorder.startCount, 1);
    expect(
      find.byKey(const ValueKey('voice-message-composer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voice-recording-indicator')),
      findsOneWidget,
    );
    expect(find.text('00:01'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('send-voice-message')));
    await tester.pumpAndSettle();

    expect(sent, same(recorder.pending));
    expect(find.byKey(const ValueKey('record-voice-message')), findsOneWidget);
    expect(recorder.deleted, isEmpty);

    release!();
    await tester.pumpAndSettle();

    expect(recorder.deleted, [same(recorder.pending)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the frames a stop hands over still count', (tester) async {
    final recorder = FakeVoiceMessageRecorder();
    addTearDown(recorder.dispose);
    final stopping = recorder.holdStop = Completer<void>();
    await tester.pumpWidget(
      _composerApp(recorder: recorder, onSendVoiceMessage: (_, _) {}),
    );

    await tester.tap(find.byKey(const ValueKey('record-voice-message')));
    await tester.pump();
    recorder.emit(
      const VoiceMessageRecordingProgress(
        duration: Duration(milliseconds: 1240),
        level: 0.8,
      ),
    );
    recorder.lastFrames = const [
      VoiceMessageRecordingProgress(
        duration: Duration(milliseconds: 2400),
        level: 0.5,
      ),
    ];
    await tester.tap(find.byKey(const ValueKey('send-voice-message')));
    await tester.pump();
    await tester.pump();

    expect(find.text('00:02'), findsOneWidget);
    stopping.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a recording does not rebuild the composer on each level', (
    tester,
  ) async {
    final recorder = FakeVoiceMessageRecorder();
    addTearDown(recorder.dispose);
    await tester.pumpWidget(
      _composerApp(recorder: recorder, onSendVoiceMessage: (_, _) {}),
    );
    await tester.tap(find.byKey(const ValueKey('record-voice-message')));
    await tester.pump();

    final builds = await countBuilds(() async {
      for (var frame = 1; frame <= 60; frame++) {
        recorder.emit(
          VoiceMessageRecordingProgress(
            duration: Duration(milliseconds: frame * 20),
            level: frame.isEven ? 0.9 : 0.2,
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    });

    expect(builds.of<MessageComposer>(), 0);
    expect(find.text('00:01'), findsOneWidget);
  });

  testWidgets('channel change cancels an active voice recording', (
    tester,
  ) async {
    final recorder = FakeVoiceMessageRecorder();
    addTearDown(recorder.dispose);
    final channelId = ValueNotifier('channel-1');
    addTearDown(channelId.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<String>(
        valueListenable: channelId,
        builder: (context, value, _) => _composerApp(
          channelId: value,
          recorder: recorder,
          onSendVoiceMessage: (_, _) {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('record-voice-message')));
    await tester.pump();

    channelId.value = 'channel-2';
    await tester.pumpAndSettle();

    expect(recorder.cancelCount, 1);
    expect(recorder.isRecording, isFalse);
    expect(find.byKey(const ValueKey('record-voice-message')), findsOneWidget);
  });

  testWidgets('a failed file cleanup does not reach the sender', (
    tester,
  ) async {
    final recorder = FakeVoiceMessageRecorder(
      deleteError: StateError('temporary file is busy'),
    );
    addTearDown(recorder.dispose);
    void Function()? release;

    await tester.pumpWidget(
      _composerApp(
        recorder: recorder,
        onSendVoiceMessage: (_, releaseFile) => release = releaseFile,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('record-voice-message')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-voice-message')));
    await tester.pumpAndSettle();
    release!();
    await tester.pumpAndSettle();

    expect(recorder.deleteCount, 1);
    expect(find.byKey(const ValueKey('record-voice-message')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _composerApp({
  String channelId = 'channel-1',
  required FakeVoiceMessageRecorder recorder,
  required SendVoiceMessageCallback onSendVoiceMessage,
}) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: MessageComposer(
        drafts: MemoryComposerDraftStore(),
        channelId: channelId,
        channelName: 'native',
        spaceName: 'Forge',
        emojiSections: const [],
        stickerSections: const [],
        isSending: false,
        voiceMessageRecorder: recorder,
        onSendVoiceMessage: onSendVoiceMessage,
        onSend: (_, _, _, _) async => true,
        onCreatePoll: (_) async => false,
        onSendStickers: (_) async => false,
        onCancelReply: () {},
        onTyping: () {},
      ),
    ),
  ),
);
