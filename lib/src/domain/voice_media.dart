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

final class VoicePcmChunk {
  VoicePcmChunk({
    required Uint8List bytes,
    required this.sampleRate,
    required this.channels,
  }) : bytes = Uint8List.fromList(bytes) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
    }
    if (channels <= 0) {
      throw ArgumentError.value(channels, 'channels', 'must be positive');
    }
    if (bytes.length.isOdd) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'must be even');
    }
  }

  final Uint8List bytes;
  final int sampleRate;
  final int channels;
}

abstract interface class VoiceMediaService {
  Object? get previewRenderer;
  Stream<VoicePcmChunk> get microphonePcm;
  Stream<void> get screenShareEnded;

  Future<void> initialize();
  Future<List<VoiceDevice>> enumerateDevices();
  Future<void> startMicrophone(String? deviceId);
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> selectAudioOutput(String deviceId);
  Future<List<VoiceCaptureSource>> enumerateCaptureSources();
  /// Starts capturing [sourceId], or the primary screen when it is null.
  ///
  /// Null is not a convenience: the platform's own default screen is more
  /// reliable than naming one. A capture source id is a handle into a list
  /// that changes when a display sleeps or is unplugged, and passing a stale
  /// one fails with "that display is no longer attached" — which is what a
  /// share of the main screen did every time.
  Future<void> startScreenShare(String? sourceId);
  Future<void> stopScreenShare();
  Future<void> stopMicrophone();
  Future<void> dispose();
}
