import 'dart:typed_data';

import 'video_encoder.dart';
import 'voice_media.dart';

final class VoiceRemoteOpusFrame {
  VoiceRemoteOpusFrame({
    required this.userId,
    required Uint8List opus,
    this.missingFramesBefore = 0,
  }) : opus = Uint8List.fromList(opus) {
    if (missingFramesBefore < 0) {
      throw RangeError.value(
        missingFramesBefore,
        'missingFramesBefore',
        'must not be negative',
      );
    }
  }

  final String userId;
  final Uint8List opus;
  final int missingFramesBefore;
}

final class VoiceRemotePcmFrame {
  VoiceRemotePcmFrame({
    required this.userId,
    required Int16List samples,
    String? sourceId,
  }) : sourceId = sourceId ?? userId,
       samples = Int16List.fromList(samples);

  /// The participant who sent the audio.
  final String userId;

  /// Playback source. Voice uses [userId]; streams use their stream key.
  final String sourceId;

  final Int16List samples;
}

/// Carries both remote audio and this account's microphone audio.
abstract interface class VoiceAudioTransport {
  Stream<VoiceRemoteOpusFrame> get remoteAudio;
  void sendOpusFrame(Uint8List opusFrame);
  Future<void> finishSpeaking();
}

/// The video half of a voice connection.
///
/// Split from [VoiceAudioTransport] because a transport can carry sound
/// without ever carrying pictures — a session with no camera, or one whose
/// build has no encoder — and a single interface would make every such
/// transport implement methods it would have to refuse.
abstract interface class VoiceVideoTransport {
  /// The SSRC Discord handed this session, or null before the voice `READY`.
  int? get audioSsrc;

  /// Declares the camera's SSRCs, or marks them inactive. Answers whether the
  /// frame could be sent at all.
  ///
  /// The settings travel whole: what the stream is declared with is what the
  /// capture runs at, and unpacking it field by field here would only let the
  /// two drift apart.
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  });
}

abstract interface class VoiceOpusEncoder {
  Uint8List encode(Int16List pcm);
  void dispose();
}

abstract interface class VoiceOpusDecoder {
  Int16List decode(Uint8List opusFrame);
  Int16List decodeFec(Uint8List opusFrame, {int frameDurationMs = 20});
  Int16List conceal({int frameDurationMs = 20});
  void dispose();
}

/// Creates decoders without requiring an encoder or microphone.
abstract interface class VoiceOpusDecoderFactory {
  VoiceOpusDecoder createDecoder();
}

abstract interface class VoiceOpusCodecFactory
    implements VoiceOpusDecoderFactory {
  VoiceOpusEncoder createEncoder();
}

abstract interface class VoiceAudioPlaybackService {
  Future<void> initialize();
  Future<List<VoiceDevice>> enumerateOutputDevices();
  Future<void> selectOutput(String deviceId);
  Future<void> setEnabled(bool enabled);
  void addPcmFrame(VoiceRemotePcmFrame frame);
  Future<void> removeSource(String sourceId);
  Future<void> dispose();
}
