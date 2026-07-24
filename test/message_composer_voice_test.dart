import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/voice_message_recorder.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('records and uploads a voice message from an empty composer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recorder = _FakeVoiceMessageRecorder();
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
      VoiceMessageRecordingProgress(
        duration: const Duration(milliseconds: 1234),
        samples: const [0.2, 0.8, 0.4],
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

  testWidgets('retains a failed upload for retry at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recorder = _FakeVoiceMessageRecorder();
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
      VoiceMessageRecordingProgress(
        duration: const Duration(seconds: 2),
        samples: const [0.3, 0.7],
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
    final recorder = _FakeVoiceMessageRecorder();
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
    final recorder = _FakeVoiceMessageRecorder(
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
  required _FakeVoiceMessageRecorder recorder,
  required SendVoiceMessageCallback onSendVoiceMessage,
}) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: MessageComposer(
        channelId: channelId,
        channelName: 'native',
        spaceName: 'Forge',
        customEmojis: const [],
        guildStickers: const [],
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

final class _FakeVoiceMessageRecorder implements VoiceMessageRecorder {
  _FakeVoiceMessageRecorder({this.deleteError});

  final StreamController<VoiceMessageRecordingProgress> _progress =
      StreamController.broadcast();
  final PendingVoiceMessage pending = PendingVoiceMessage(
    name: 'voice.ogg',
    path: 'C:\\temp\\voice.ogg',
    size: 128,
    durationSecs: 2,
    waveform: 'AQID',
  );
  final List<PendingVoiceMessage> deleted = [];
  final Object? deleteError;

  int startCount = 0;
  int cancelCount = 0;
  int deleteCount = 0;

  @override
  bool isRecording = false;

  @override
  Stream<VoiceMessageRecordingProgress> get progress => _progress.stream;

  void emit(VoiceMessageRecordingProgress value) => _progress.add(value);

  @override
  Future<void> start() async {
    startCount++;
    isRecording = true;
  }

  @override
  Future<PendingVoiceMessage> stop() async {
    isRecording = false;
    return pending;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    isRecording = false;
  }

  @override
  Future<void> delete(PendingVoiceMessage message) async {
    deleteCount++;
    if (deleteError case final error?) throw error;
    deleted.add(message);
  }

  @override
  Future<void> dispose() async {
    if (!_progress.isClosed) await _progress.close();
  }
}
