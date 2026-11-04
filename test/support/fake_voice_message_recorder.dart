import 'dart:async';

import 'package:flucord/src/domain/voice_message_recorder.dart';

/// A recorder with no microphone. A test reads its counts and feeds [emit].
final class FakeVoiceMessageRecorder implements VoiceMessageRecorder {
  /// [pending] is what [stop] hands back; a test that uploads it passes one
  /// whose file exists.
  FakeVoiceMessageRecorder({this.deleteError, PendingVoiceMessage? pending})
    : pending =
          pending ??
          PendingVoiceMessage(
            name: 'voice.ogg',
            path: 'C:\\temp\\voice.ogg',
            size: 128,
            durationSecs: 2,
            waveform: 'AQID',
          );

  final StreamController<VoiceMessageRecordingProgress> _progress =
      StreamController.broadcast();
  final PendingVoiceMessage pending;
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
