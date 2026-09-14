final class VoiceMessageRecordingProgress {
  VoiceMessageRecordingProgress({
    required this.duration,
    required List<double> samples,
  }) : samples = List.unmodifiable(samples);

  final Duration duration;
  final List<double> samples;
}

final class PendingVoiceMessage {
  PendingVoiceMessage({
    required this.name,
    required this.path,
    required this.size,
    required this.durationSecs,
    required this.waveform,
  }) {
    if (name.isEmpty || path.isEmpty || size <= 0) {
      throw ArgumentError('Voice message file metadata is invalid');
    }
    if (durationSecs <= 0 || waveform.isEmpty) {
      throw ArgumentError('Voice message audio metadata is invalid');
    }
  }

  final String name;
  final String path;
  final int size;
  final double durationSecs;
  final String waveform;
}

abstract interface class VoiceMessageRecorder {
  Stream<VoiceMessageRecordingProgress> get progress;
  bool get isRecording;

  Future<void> start();
  Future<PendingVoiceMessage> stop();
  Future<void> cancel();
  Future<void> delete(PendingVoiceMessage message);
  Future<void> dispose();
}
