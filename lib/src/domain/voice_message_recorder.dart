import 'chat_models.dart';

/// One 20 ms frame of a recording in progress.
final class VoiceMessageRecordingProgress {
  const VoiceMessageRecordingProgress({
    required this.duration,
    required this.level,
  });

  /// How much has been recorded, up to the end of this frame.
  final Duration duration;

  /// The frame's peak, from 0 (silence) to 1, on the waveform's scale.
  final double level;
}

abstract interface class VoiceMessageRecorder {
  /// One event per recorded frame. A capture failure arrives as an error.
  Stream<VoiceMessageRecordingProgress> get progress;
  bool get isRecording;

  Future<void> start();
  Future<PendingVoiceMessage> stop();
  Future<void> cancel();
  Future<void> delete(PendingVoiceMessage message);
  Future<void> dispose();
}
