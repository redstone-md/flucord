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

    await tester.pumpWidget(
      _composerApp(
        recorder: recorder,
        onSendVoiceMessage: (message) async {
          sent = message;
          return true;
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
    expect(recorder.deleted, [same(recorder.pending)]);
    expect(find.byKey(const ValueKey('record-voice-message')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recording does not rebuild the composer on each level', (
    tester,
  ) async {
    final recorder = FakeVoiceMessageRecorder();
    addTearDown(recorder.dispose);
    await tester.pumpWidget(
      _composerApp(recorder: recorder, onSendVoiceMessage: (_) async => true),
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

  testWidgets('retains a failed upload for retry at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recorder = FakeVoiceMessageRecorder();
    addTearDown(recorder.dispose);
    var attempts = 0;

    await tester.pumpWidget(
      _composerApp(
        recorder: recorder,
        onSendVoiceMessage: (_) async => ++attempts > 1,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('record-voice-message')));
    await tester.pump();
    recorder.emit(
      const VoiceMessageRecordingProgress(
        duration: Duration(seconds: 2),
        level: 0.7,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-voice-message')));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.byKey(const ValueKey('retry-voice-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-voice-message')), findsOneWidget);
    expect(recorder.deleted, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('retry-voice-message')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(recorder.deleted, [same(recorder.pending)]);
    expect(find.byKey(const ValueKey('record-voice-message')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
          onSendVoiceMessage: (_) async => true,
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

  testWidgets('cleanup failure cannot turn a successful upload into a retry', (
    tester,
  ) async {
    final recorder = FakeVoiceMessageRecorder(
      deleteError: StateError('temporary file is busy'),
    );
    addTearDown(recorder.dispose);
    var sends = 0;

    await tester.pumpWidget(
      _composerApp(
        recorder: recorder,
        onSendVoiceMessage: (_) async {
          sends++;
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('record-voice-message')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-voice-message')));
    await tester.pumpAndSettle();

    expect(sends, 1);
    expect(recorder.deleteCount, 1);
    expect(find.byKey(const ValueKey('retry-voice-message')), findsNothing);
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
