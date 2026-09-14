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

/// The microphone and speaker half of a voice session.
///
/// Deliberately without any screen capture: the machine's display is captured
/// by the capture and encode module (`VideoCaptureHub`), which is the one
/// path to a duplication. A second capture opened here was exactly what
/// refused the share on the machines that could least afford it.
abstract interface class VoiceMediaService {
  Stream<VoicePcmChunk> get microphonePcm;

  Future<void> initialize();
  Future<List<VoiceDevice>> enumerateDevices();
  Future<void> startMicrophone(String? deviceId);
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> selectAudioOutput(String deviceId);
  Future<void> stopMicrophone();
  Future<void> dispose();
}
