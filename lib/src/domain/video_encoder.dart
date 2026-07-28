import 'dart:typed_data';

/// One encoded picture, ready for the RTP sender.
final class EncodedVideoFrame {
  const EncodedVideoFrame({
    required this.bytes,
    required this.timestamp,
    required this.isKeyframe,
  });

  /// An Annex B access unit.
  final Uint8List bytes;

  final Duration timestamp;

  /// Whether a viewer joining now could start decoding here.
  final bool isKeyframe;
}

/// What a stream is being encoded at.
final class VideoEncoderSettings {
  const VideoEncoderSettings({
    this.displayIndex = 0,
    this.width = 1280,
    this.height = 720,
    this.framesPerSecond = 30,
    this.bitrate = 2500000,
  });

  final int displayIndex;
  final int width;
  final int height;
  final int framesPerSecond;

  /// Bits per second. Discord's own default for a 720p30 share.
  final int bitrate;

  bool get isValid =>
      width > 0 &&
      height > 0 &&
      framesPerSecond > 0 &&
      bitrate > 0 &&
      displayIndex >= 0;
}

/// Why the encoder could not start.
enum VideoEncoderFailure {
  /// No H.264 encoder, or no Direct3D device to capture with.
  unsupported,

  /// The display asked for is not there.
  noDisplay,

  /// The encoder rejected the settings.
  encoder,

  /// The call itself was wrong — bad settings, or already running.
  state,
}

final class VideoEncoderException implements Exception {
  const VideoEncoderException(this.failure);

  final VideoEncoderFailure failure;

  String get message => switch (failure) {
    VideoEncoderFailure.unsupported =>
      'This machine has no usable H.264 encoder.',
    VideoEncoderFailure.noDisplay => 'That display is no longer attached.',
    VideoEncoderFailure.encoder => 'The encoder refused those settings.',
    VideoEncoderFailure.state => 'The encoder is already running.',
  };

  @override
  String toString() => message;
}

/// Turns a display into encoded frames.
///
/// Deliberately not a WebRTC track: Go Live carries its own RTP over the voice
/// socket, so what this client needs is the encoded bytes rather than a track
/// somebody else would send.
abstract interface class VideoEncoderService {
  /// Whether this platform can encode at all.
  bool get isSupported;

  /// How many displays there are to choose from.
  int get displayCount;

  /// Encoded frames, from the moment [start] returns until [stop].
  Stream<EncodedVideoFrame> get frames;

  Future<void> start(VideoEncoderSettings settings);

  /// Asks for a keyframe, which is what a viewer joining midway needs.
  Future<void> requestKeyframe();

  /// Holds frames back without tearing the encoder down.
  Future<void> setPaused({required bool paused});

  Future<void> stop();
}
