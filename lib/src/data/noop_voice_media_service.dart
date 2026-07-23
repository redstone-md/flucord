import '../domain/voice_media.dart';

final class NoopVoiceMediaService implements VoiceMediaService {
  const NoopVoiceMediaService();

  @override
  Object? get previewRenderer => null;

  @override
  Stream<VoicePcmChunk> get microphonePcm => const Stream.empty();

  @override
  Stream<void> get screenShareEnded => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [];

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async => const [];

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> startScreenShare(String sourceId) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> stopScreenShare() async {}

  @override
  Future<void> dispose() async {}
}
