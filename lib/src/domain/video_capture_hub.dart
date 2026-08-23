import 'stream_quality.dart';
import 'video_encoder.dart';

/// The machine's one capture and encode resource.
///
/// One encoder serves everybody who wants local pictures: a Go Live share, the
/// camera, the clip buffer. Windows allows only one duplication of a display,
/// and one encoder instance can only run one set of settings, so a second
/// capture while one runs is refused outright rather than queued. That refusal
/// is the whole arbitration, and it is what makes a double capture impossible
/// to construct: there is no path to a second native handle.
final class VideoCaptureHub {
  VideoCaptureHub({required VideoEncoderService encoder}) : _encoder = encoder;

  /// The bitrates the next share or camera starts at.
  ///
  /// Read at start, not listened to: a capture that is already running keeps
  /// the settings it began with, and the next one takes whatever this says by
  /// then. The settings plane writes it; the numbers themselves are named
  /// nowhere but [StreamQualitySettings].
  StreamQualitySettings quality = const StreamQualitySettings();

  final VideoEncoderService _encoder;

  /// What a screen share would start at now: the quality's bitrate on the
  /// share profile (720p30, the shape Discord's protocol announces).
  VideoEncoderSettings get shareSettings =>
      VideoEncoderSettings(bitrate: quality.shareBitrate);

  /// What the camera would start at now: Discord sends camera video
  /// considerably smaller than a share, and a webcam picture carries far less
  /// detail than a desktop full of text.
  VideoEncoderSettings get cameraSettings =>
      VideoEncoderSettings.camera(bitrate: quality.cameraBitrate);

  bool _running = false;
  VideoEncoderSettings? _settings;

  /// Whether this build can encode at all.
  bool get isSupported => _encoder.isSupported;

  /// How many displays there are to choose from.
  int get displayCount => _encoder.displayCount;

  /// The cameras attached, by name, in the order the platform lists them.
  List<String> get cameraNames => _encoder.cameraNames;

  /// Encoded frames, from whichever capture is running.
  Stream<EncodedVideoFrame> get frames => _encoder.frames;

  /// The native pipeline's own account of itself, for the pace log.
  VideoEncoderDiagnostics? get diagnostics => _encoder.diagnostics;

  bool get isCapturing => _running;

  /// What the running capture started with, or what the last one did.
  ///
  /// Kept after [stop] on purpose: the clip buffer outlives the capture, and
  /// writing its frames to a file needs to know what they were encoded at.
  VideoEncoderSettings? get settings => _settings;

  /// Starts capturing a display, answering the settings it runs at.
  Future<VideoEncoderSettings> startShare({int displayIndex = 0}) =>
      _start(shareSettings.onSource(displayIndex));

  /// Starts capturing a camera, answering the settings it runs at.
  Future<VideoEncoderSettings> startCamera({int cameraIndex = 0}) =>
      _start(cameraSettings.onSource(cameraIndex));

  Future<VideoEncoderSettings> _start(VideoEncoderSettings settings) async {
    if (_running) {
      throw const VideoEncoderException(VideoEncoderFailure.state);
    }
    // Claimed before the await, not after: two overlapping starts would both
    // pass the check above while the first was still opening, and the guard
    // after the await is only a hope. The claim and the check are one
    // synchronous step, which is what makes the refusal a construction.
    _running = true;
    try {
      await _encoder.start(settings);
    } on Object {
      _running = false;
      rethrow;
    }
    _settings = settings;
    return settings;
  }

  /// Asks for a keyframe, which is what a viewer joining midway needs.
  Future<void> requestKeyframe() => _encoder.requestKeyframe();

  /// Holds frames back without tearing the capture down.
  Future<void> setPaused({required bool paused}) =>
      _encoder.setPaused(paused: paused);

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _encoder.stop();
  }
}
