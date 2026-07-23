import 'dart:typed_data';

enum VoiceDeviceKind { audioInput, audioOutput }

final class VoiceDevice {
  const VoiceDevice({
    required this.id,
    required this.label,
    required this.kind,
  });

  final String id;
  final String label;
  final VoiceDeviceKind kind;
}

enum VoiceCaptureKind { screen, window }

final class VoiceCaptureSource {
  const VoiceCaptureSource({
    required this.id,
    required this.name,
    required this.kind,
    this.thumbnail,
  });

  final String id;
  final String name;
  final VoiceCaptureKind kind;
  final Uint8List? thumbnail;
}

abstract interface class VoiceMediaService {
  Object? get previewRenderer;
  Stream<void> get screenShareEnded;

  Future<void> initialize();
  Future<List<VoiceDevice>> enumerateDevices();
  Future<void> startMicrophone(String? deviceId);
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> selectAudioOutput(String deviceId);
  Future<List<VoiceCaptureSource>> enumerateCaptureSources();
  Future<void> startScreenShare(String sourceId);
  Future<void> stopScreenShare();
  Future<void> stopMicrophone();
  Future<void> dispose();
}
