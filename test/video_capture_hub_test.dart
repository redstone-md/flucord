import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/domain/stream_quality.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the two profiles follow the quality, and name no bitrates of their own',
    () {
      final hub = VideoCaptureHub(encoder: _FakeEncoder());

      // A share carries a desktop full of text; a camera picture carries far
      // less. Discord's own defaults: 2.5 Mbit for a 720p30 share, half that
      // for a camera.
      expect(hub.shareSettings.bitrate, 2500000);
      expect(hub.shareSettings.source, VideoCaptureSource.display);
      expect(hub.shareSettings.width, 1280);
      expect(hub.shareSettings.height, 720);
      expect(hub.shareSettings.framesPerSecond, 30);

      expect(hub.cameraSettings.bitrate, 1200000);
      expect(hub.cameraSettings.source, VideoCaptureSource.camera);
    },
  );

  test('a quality change is what the next capture starts at', () async {
    final encoder = _FakeEncoder();
    final hub = VideoCaptureHub(encoder: encoder);

    hub.quality = const StreamQualitySettings(
      shareBitrate: 5000000,
      cameraBitrate: 300000,
    );
    expect((await hub.startShare()).bitrate, 5000000);
    await hub.stop();
    expect((await hub.startCamera()).bitrate, 300000);
  });

  test('a share and a camera both start through their profile', () async {
    final encoder = _FakeEncoder();
    final hub = VideoCaptureHub(encoder: encoder);

    final share = await hub.startShare(displayIndex: 2);
    expect(encoder.started.single, share);
    expect(share.displayIndex, 2);
    expect(share.bitrate, 2500000);
    await hub.stop();

    final camera = await hub.startCamera(cameraIndex: 1);
    expect(camera.source, VideoCaptureSource.camera);
    expect(camera.displayIndex, 1);
    expect(camera.bitrate, 1200000);
  });

  test(
    'a second capture while one runs is refused, and the first survives',
    () async {
      final encoder = _FakeEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      await hub.startShare();

      await expectLater(
        hub.startCamera(),
        throwsA(
          isA<VideoEncoderException>().having(
            (error) => error.failure,
            'failure',
            VideoEncoderFailure.state,
          ),
        ),
      );

      // The refusal happened before the encoder was touched, so the share is
      // still the capture that is running.
      expect(encoder.started.length, 1);
      expect(hub.isCapturing, isTrue);
      expect(hub.settings!.source, VideoCaptureSource.display);
    },
  );

  test('two overlapping starts: only one reaches the encoder', () async {
    // A start that has not finished yet: the guard must hold from the moment
    // the first start is called, not from the moment it completes.
    final encoder = _FakeEncoder()..gate = Completer<void>();
    final hub = VideoCaptureHub(encoder: encoder);

    final first = hub.startShare();
    await expectLater(
      hub.startCamera(),
      throwsA(
        isA<VideoEncoderException>().having(
          (error) => error.failure,
          'failure',
          VideoEncoderFailure.state,
        ),
      ),
    );
    expect(encoder.started, isEmpty);

    encoder.gate!.complete();
    await first;
    expect(encoder.started, hasLength(1));
    expect(encoder.started.single.source, VideoCaptureSource.display);
  });

  test('a start the encoder refuses leaves the module free', () async {
    final encoder = _FakeEncoder()..failStart = true;
    final hub = VideoCaptureHub(encoder: encoder);

    await expectLater(hub.startShare(), throwsStateError);
    expect(hub.isCapturing, isFalse);

    // The failed attempt is not remembered as a running capture, so the next
    // one does not have to fight a phantom.
    encoder.failStart = false;
    await hub.startShare();
    expect(hub.isCapturing, isTrue);
  });

  test(
    'the settings outlive the capture, because the clip buffer does',
    () async {
      final encoder = _FakeEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      await hub.startCamera();
      await hub.stop();

      expect(hub.isCapturing, isFalse);
      expect(hub.settings, hub.cameraSettings);

      // Stopped again: nothing to stop, and the encoder is not asked twice.
      await hub.stop();
      expect(encoder.stopped, 1);
    },
  );

  test('frames and keyframe requests reach whoever attached', () async {
    final encoder = _FakeEncoder();
    final hub = VideoCaptureHub(encoder: encoder);
    final frames = <EncodedVideoFrame>[];
    hub.frames.listen(frames.add);

    await hub.startShare();
    encoder.emit();
    await hub.requestKeyframe();
    await hub.setPaused(paused: true);

    expect(frames, hasLength(1));
    expect(encoder.keyframes, 1);
    expect(encoder.pauses, [true]);
  });
}

final class _FakeEncoder implements VideoEncoderService {
  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  /// When set, a start waits on it before finishing, so a test can hold one
  /// capture mid-open.
  Completer<void>? gate;

  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();
  final List<VideoEncoderSettings> started = [];
  final List<bool> pauses = [];
  int stopped = 0;
  int keyframes = 0;
  bool failStart = false;

  void emit() => _frames.add(
    EncodedVideoFrame(
      bytes: Uint8List.fromList([0, 0, 0, 1, 0x65, 1, 2, 3]),
      timestamp: Duration.zero,
      isKeyframe: true,
    ),
  );

  @override
  bool get isSupported => true;

  @override
  int get displayCount => 1;

  @override
  List<String> get cameraNames => const ['Webcam'];

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start(VideoEncoderSettings settings) async {
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (failStart) throw StateError('no encoder');
    started.add(settings);
  }

  @override
  Future<void> requestKeyframe() async => keyframes++;

  @override
  Future<void> setPaused({required bool paused}) async => pauses.add(paused);

  @override
  Future<void> stop() async => stopped++;
}
