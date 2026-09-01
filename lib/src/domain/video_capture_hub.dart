import 'dart:async';

import 'stream_quality.dart';
import 'video_encoder.dart';

/// Where a share's pictures go when they leave the encoder natively, and how
/// they come back for whoever listens on the main isolate.
abstract interface class ShareFrameDestination {
  /// A native address the encoder delivers to directly, or null to keep the
  /// frames in-process.
  Future<int?> get nativeFrameSink;

  /// The frames delivered there, echoed back.
  Stream<EncodedVideoFrame> get relayedFrames;
}

/// The machine's one capture and encode resource.
///
/// One encoder serves everybody who wants local pictures: a Go Live share, the
/// camera, the clip buffer. Windows allows only one duplication of a display,
/// and one encoder instance can only run one set of settings, so a second
/// capture while one runs is refused outright rather than queued. That refusal
/// is the whole arbitration, and it is what makes a double capture impossible
/// to construct: there is no path to a second native handle.
///
/// Starting a capture hands the starter a [VideoCaptureLease], and only the
/// lease steers or stops what it started. Nobody needs to remember whether the
/// running capture is theirs: a lease that is not the running one does nothing.
final class VideoCaptureHub {
  VideoCaptureHub({
    required VideoEncoderService encoder,
    ShareFrameDestination? shareFrames,
    void Function(String line)? onDiagnostic,
  }) : _encoder = encoder,
       _shareFrames = shareFrames,
       _diagnose = onDiagnostic {
    _encoder.frames.listen(_frames.add, onError: _frames.addError);
    shareFrames?.relayedFrames.listen(_frames.add);
  }

  final VideoEncoderService _encoder;

  /// Where a share's frames are delivered. Without one, they arrive on
  /// [frames] like a camera's do.
  final ShareFrameDestination? _shareFrames;
  final void Function(String line)? _diagnose;

  StreamQualitySettings _quality = const StreamQualitySettings();

  /// The bitrates and the share shape the next capture starts at. The
  /// settings plane writes it; the numbers themselves are named nowhere but
  /// [StreamQualitySettings].
  StreamQualitySettings get quality => _quality;

  /// Sets [quality], and brings a running share to it: a bitrate alone
  /// changes on the running encoder; a new size or frame rate restarts the
  /// encoder under the same lease, because an encoder is built for one shape.
  /// Either way the lease reports what it runs at now. A camera keeps what it
  /// started with. Completes once the running share has been brought over.
  Future<void> setQuality(StreamQualitySettings quality) {
    _quality = quality;
    return _serial(_bringShareToQuality);
  }

  /// What a screen share would start at now: the shape and frame rate the
  /// quality names, at the bitrate scaled for them.
  VideoEncoderSettings get shareSettings => VideoEncoderSettings(
    bitrate: _quality.shareEncodeBitrate,
    width: _quality.shareResolution.width,
    height: _quality.shareResolution.height,
    framesPerSecond: _quality.shareFrameRate,
  );

  /// What the camera would start at now: Discord sends camera video
  /// considerably smaller than a share, and a webcam picture carries far less
  /// detail than a desktop full of text.
  VideoEncoderSettings get cameraSettings =>
      VideoEncoderSettings.camera(bitrate: _quality.cameraBitrate);

  VideoCaptureLease? _lease;
  VideoEncoderSettings? _settings;

  /// Whether this build can encode at all.
  bool get isSupported => _encoder.isSupported;

  /// How many displays there are to choose from.
  int get displayCount => _encoder.displayCount;

  /// The cameras attached, by name, in the order the platform lists them.
  List<String> get cameraNames => _encoder.cameraNames;

  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();

  /// Encoded frames, from whichever capture is running: the encoder's own,
  /// or the ones the share's destination echoes back.
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  /// The native pipeline's own account of itself, for the pace log.
  VideoEncoderDiagnostics? get diagnostics => _encoder.diagnostics;

  bool get isCapturing => _lease != null;

  /// What the running capture runs at, or what the last one did.
  ///
  /// Kept after the lease is released on purpose: the clip buffer outlives
  /// the capture, and writing its frames to a file needs to know what they
  /// were encoded at.
  VideoEncoderSettings? get settings => _settings;

  /// Starts capturing a display, delivering to the share destination.
  Future<VideoCaptureLease> startShare({int displayIndex = 0}) =>
      _start(shareSettings.onSource(displayIndex));

  /// Starts capturing a camera.
  Future<VideoCaptureLease> startCamera({int cameraIndex = 0}) =>
      _start(cameraSettings.onSource(cameraIndex));

  Future<VideoCaptureLease> _start(VideoEncoderSettings settings) async {
    if (_lease != null) {
      throw const VideoEncoderException(VideoEncoderFailure.state);
    }
    // Claimed before the first await, not after: two overlapping starts would
    // both pass the check above while the first was still opening. The claim
    // and the check are one synchronous step, which is what makes the refusal
    // a construction.
    final lease = _lease = VideoCaptureLease._(this, settings);
    try {
      await _serial(() => _run(lease, settings));
    } on Object {
      _lease = null;
      rethrow;
    }
    return lease;
  }

  /// Runs the encoder at [settings] for [lease], where its frames belong.
  Future<void> _run(
    VideoCaptureLease lease,
    VideoEncoderSettings settings,
  ) async {
    final Object encoder = _encoder;
    if (encoder is VideoFrameSinkControl) {
      encoder.nativeFrameSink = lease._isShare
          ? await _shareFrames?.nativeFrameSink
          : null;
    }
    await _encoder.start(settings);
    if (lease._paused) await _encoder.setPaused(paused: true);
    _adopt(lease, settings);
  }

  /// Records what [lease] runs at now. A lease released meanwhile keeps its
  /// own record, but the hub's says what the encoder is doing.
  void _adopt(VideoCaptureLease lease, VideoEncoderSettings settings) {
    lease._settings = settings;
    if (identical(_lease, lease)) _settings = settings;
  }

  Future<void> _bringShareToQuality() async {
    final lease = _lease;
    if (lease == null || !lease._isShare) return;
    final running = lease._settings;
    final wanted = shareSettings.onSource(running.displayIndex);
    if (wanted == running) return;
    try {
      if (running.hasShapeOf(wanted)) {
        await _setBitrate(lease, wanted.bitrate);
      } else {
        await _encoder.stop();
        // Released while the encoder was stopping: nothing to bring over.
        if (!identical(_lease, lease)) return;
        await _run(lease, wanted);
      }
    } on Object catch (error, stack) {
      if (!identical(_lease, lease)) return;
      // Nothing is running any more, so nothing is held: the holder hears
      // why, and the next capture does not have to fight a phantom.
      _lease = null;
      lease._changes.addError(error, stack);
      await lease._changes.close();
      return;
    }
    if (identical(_lease, lease)) lease._changes.add(wanted);
  }

  Future<bool> _setBitrate(VideoCaptureLease lease, int bitsPerSecond) async {
    // Typed as Object so the check can promote: the control is a second
    // interface, not a subtype of the service.
    final Object encoder = _encoder;
    final accepted =
        encoder is VideoBitrateControl &&
        await encoder.setBitrate(bitsPerSecond);
    if (accepted) {
      _adopt(lease, lease._settings.withBitrate(bitsPerSecond));
    } else if (!lease._bitrateRefusalLogged) {
      lease._bitrateRefusalLogged = true;
      _diagnose?.call('bitrate: encoder keeps its rate; only the pace follows');
    }
    return accepted;
  }

  Future<void> _release(VideoCaptureLease lease) async {
    if (!identical(_lease, lease)) return;
    _lease = null;
    await _serial(() async {
      await _encoder.stop();
      await lease._changes.close();
    });
  }

  Future<void> _queue = Future.value();

  /// Runs [work] after whatever the encoder is already being asked to do: a
  /// release or a pause must not overtake a restart that is half way through.
  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// A running capture, held by whoever started it.
///
/// Only the holder steers or stops what it started. Every member is a no-op
/// once released, or once a newer capture has taken the holder's place, and
/// releasing twice is harmless.
final class VideoCaptureLease {
  VideoCaptureLease._(this._hub, this._settings);

  final VideoCaptureHub _hub;
  VideoEncoderSettings _settings;
  bool _paused = false;
  bool _bitrateRefusalLogged = false;
  final StreamController<VideoEncoderSettings> _changes =
      StreamController.broadcast();

  /// What the capture runs at now.
  VideoEncoderSettings get settings => _settings;

  /// What the capture runs at after a quality change brought it somewhere
  /// else; a restart the encoder refused arrives as an error.
  Stream<VideoEncoderSettings> get settingsChanges => _changes.stream;

  bool get _isShare => _settings.source == VideoCaptureSource.display;

  bool get _isLive => identical(_hub._lease, this);

  /// Changes the bitrate from the next picture on. False when the encoder
  /// cannot, in which case it keeps its rate.
  Future<bool> setBitrate(int bitsPerSecond) => _hub._serial(
    () => _isLive ? _hub._setBitrate(this, bitsPerSecond) : Future.value(false),
  );

  /// Asks for a keyframe, which is what a viewer joining midway needs.
  Future<void> requestKeyframe() => _hub._serial(
    () => _isLive ? _hub._encoder.requestKeyframe() : Future.value(),
  );

  /// Holds frames back without tearing the capture down.
  Future<void> setPaused({required bool paused}) => _hub._serial(() {
    if (!_isLive) return Future.value();
    _paused = paused;
    return _hub._encoder.setPaused(paused: paused);
  });

  /// Stops the capture.
  Future<void> release() => _hub._release(this);
}
