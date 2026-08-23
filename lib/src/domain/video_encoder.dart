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

/// Where the pictures come from.
///
/// The two share everything downstream of the capture — the same encoder, the
/// same packetiser, the same socket — but they are not the same feature on
/// Discord: a screen is a Go Live stream with its own SSRC and its own
/// viewers, and a camera is the account's own video in the room it is sitting
/// in, announced with `self_video` on the voice state.
enum VideoCaptureSource { display, camera }

/// What a stream is being encoded at.
///
/// A value object: a share or a camera profile is assembled in
/// [VideoCaptureHub] from the [StreamQualitySettings] the settings plane
/// holds, which is the one place that names a bitrate.
final class VideoEncoderSettings {
  const VideoEncoderSettings({
    required this.bitrate,
    this.source = VideoCaptureSource.display,
    this.displayIndex = 0,
    this.width = 1280,
    this.height = 720,
    this.framesPerSecond = 30,
  });

  const VideoEncoderSettings.camera({
    required this.bitrate,
    this.displayIndex = 0,
    this.width = 1280,
    this.height = 720,
    this.framesPerSecond = 30,
  }) : source = VideoCaptureSource.camera;

  final VideoCaptureSource source;

  /// Which display, or which camera when [source] is a camera.
  final int displayIndex;
  final int width;
  final int height;
  final int framesPerSecond;

  /// Bits per second.
  final int bitrate;

  /// The same settings pointed at another source: a display index, or a
  /// camera index when [source] is a camera.
  VideoEncoderSettings onSource(int index) => VideoEncoderSettings(
    source: source,
    displayIndex: index,
    width: width,
    height: height,
    framesPerSecond: framesPerSecond,
    bitrate: bitrate,
  );

  bool get isValid =>
      width > 0 &&
      height > 0 &&
      framesPerSecond > 0 &&
      bitrate > 0 &&
      displayIndex >= 0;

  @override
  bool operator ==(Object other) =>
      other is VideoEncoderSettings &&
      other.source == source &&
      other.displayIndex == displayIndex &&
      other.width == width &&
      other.height == height &&
      other.framesPerSecond == framesPerSecond &&
      other.bitrate == bitrate;

  @override
  int get hashCode => Object.hash(
    source,
    displayIndex,
    width,
    height,
    framesPerSecond,
    bitrate,
  );
}

/// Why the encoder could not start.
enum VideoEncoderFailure {
  /// No H.264 encoder, or no Direct3D device to capture with.
  unsupported,

  /// The display asked for is not there.
  noDisplay,

  /// No camera at that index, or another application is holding it.
  noCamera,

  /// The encoder rejected the settings.
  encoder,

  /// The call itself was wrong — bad settings, or already running.
  state,
}

final class VideoEncoderException implements Exception {
  const VideoEncoderException(
    this.failure, {
    this.platformCode,
    this.platformStage,
  });

  final VideoEncoderFailure failure;

  /// What the platform itself said, where it says anything — an HRESULT on
  /// Windows. "No display" covers a machine with no output, an index that has
  /// gone, and a duplication another process is holding, and only this
  /// separates them.
  final int? platformCode;

  /// Which call produced [platformCode], where the platform reports one.
  final int? platformStage;

  String get message => switch (failure) {
    VideoEncoderFailure.unsupported =>
      'This machine has no usable H.264 encoder.',
    VideoEncoderFailure.noDisplay => 'That display is no longer attached.',
    VideoEncoderFailure.noCamera =>
      'That camera is not there, or another application is using it.',
    VideoEncoderFailure.encoder => 'The encoder refused those settings.',
    VideoEncoderFailure.state => 'The encoder is already running.',
  };

  String get _platformSuffix {
    if (platformCode == null || platformCode == 0) return '';
    final code = '0x${platformCode!.toUnsigned(32).toRadixString(16)}';
    final stage = platformStage == null || platformStage == 0
        ? ''
        : ' at step $platformStage';
    return ' ($code$stage)';
  }

  @override
  String toString() => '$message$_platformSuffix';
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

  /// The cameras attached, by name, in the order the platform lists them.
  ///
  /// Names rather than a count, because one webcam looks like another in a
  /// list of indexes and a machine with two of them is the case that needs
  /// choosing at all.
  List<String> get cameraNames;

  /// Encoded frames, from the moment [start] returns until [stop].
  Stream<EncodedVideoFrame> get frames;

  Future<void> start(VideoEncoderSettings settings);

  /// Asks for a keyframe, which is what a viewer joining midway needs.
  Future<void> requestKeyframe();

  /// Holds frames back without tearing the encoder down.
  Future<void> setPaused({required bool paused});

  Future<void> stop();
}
