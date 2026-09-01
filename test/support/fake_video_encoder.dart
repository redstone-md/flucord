import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/domain/video_encoder.dart';

/// The one encoder every capture test drives.
///
/// Records what the hub asked of it (starts, stops, bitrates, keyframes,
/// pauses, where each start was told to deliver) and emits a picture when a
/// test says so. Failures are opted into per test.
final class FakeVideoEncoder
    implements VideoEncoderService, VideoBitrateControl, VideoFrameSinkControl {
  FakeVideoEncoder({
    this.supported = true,
    int displays = 1,
    this.cameras = const ['Webcam'],
  }) : _displays = displays;

  final bool supported;
  final int _displays;
  List<String> cameras;

  /// Every start, in order. The last one is what runs now.
  final List<VideoEncoderSettings> started = [];
  final List<int> bitrates = [];
  final List<bool> pauses = [];

  /// Where each start was told to deliver frames.
  final List<int?> frameSinks = [];
  int stopped = 0;
  int keyframes = 0;

  /// Thrown by the next start, when set.
  Object? startFailure;
  bool failStop = false;

  /// Whether a bitrate change is taken. An encoder that cannot change rate
  /// answers false and keeps what it started with.
  bool acceptsBitrate = true;

  /// When set, a start waits on it before finishing, so a test can hold one
  /// capture mid-open.
  Completer<void>? gate;

  int? _frameSink;
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();

  /// A start code and a NAL header: enough for the packetiser to build one
  /// single-unit packet from.
  static final Uint8List keyframeBytes = Uint8List.fromList([
    0,
    0,
    0,
    1,
    0x65,
    1,
    2,
    3,
  ]);

  /// Emits [frame], or one small keyframe, as the capture would.
  void emit([EncodedVideoFrame? frame]) => _frames.add(
    frame ??
        EncodedVideoFrame(
          bytes: keyframeBytes,
          timestamp: Duration.zero,
          isKeyframe: true,
        ),
  );

  Future<void> close() => _frames.close();

  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  @override
  bool get isSupported => supported;

  @override
  int get displayCount => supported ? _displays : 0;

  @override
  List<String> get cameraNames => cameras;

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  set nativeFrameSink(int? address) => _frameSink = address;

  @override
  Future<void> start(VideoEncoderSettings settings) async {
    final gate = this.gate;
    if (gate != null) await gate.future;
    final failure = startFailure;
    if (failure != null) throw failure;
    started.add(settings);
    frameSinks.add(_frameSink);
  }

  @override
  Future<bool> setBitrate(int bitsPerSecond) async {
    bitrates.add(bitsPerSecond);
    return acceptsBitrate;
  }

  @override
  Future<void> requestKeyframe() async => keyframes++;

  @override
  Future<void> setPaused({required bool paused}) async => pauses.add(paused);

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('already gone');
    stopped++;
  }
}
