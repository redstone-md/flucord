import 'dart:async';

import 'package:flucord/src/domain/stream_quality.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_video_encoder.dart';

Matcher _refused(VideoEncoderFailure failure) => throwsA(
  isA<VideoEncoderException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  test(
    'the two profiles follow the quality, and name no bitrates of their own',
    () {
      final hub = VideoCaptureHub(encoder: FakeVideoEncoder());

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
    final hub = VideoCaptureHub(encoder: FakeVideoEncoder());

    await hub.setQuality(
      const StreamQualitySettings(shareBitrate: 5000000, cameraBitrate: 300000),
    );
    final share = await hub.startShare();
    expect(share.settings.bitrate, 5000000);
    await share.release();
    final camera = await hub.startCamera();
    expect(camera.settings.bitrate, 300000);
  });

  test('a share and a camera both start through their profile', () async {
    final encoder = FakeVideoEncoder();
    final hub = VideoCaptureHub(encoder: encoder);

    final share = await hub.startShare(displayIndex: 2);
    expect(encoder.started.single, share.settings);
    expect(share.settings.displayIndex, 2);
    expect(share.settings.bitrate, 2500000);
    await share.release();

    final camera = await hub.startCamera(cameraIndex: 1);
    expect(camera.settings.source, VideoCaptureSource.camera);
    expect(camera.settings.displayIndex, 1);
    expect(camera.settings.bitrate, 1200000);
  });

  test(
    'a second capture while one runs is refused, and the first survives',
    () async {
      final encoder = FakeVideoEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      await hub.startShare();

      await expectLater(hub.startCamera(), _refused(VideoEncoderFailure.state));

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
    final encoder = FakeVideoEncoder()..gate = Completer<void>();
    final hub = VideoCaptureHub(encoder: encoder);

    final first = hub.startShare();
    await expectLater(hub.startCamera(), _refused(VideoEncoderFailure.state));
    expect(encoder.started, isEmpty);

    encoder.gate!.complete();
    await first;
    expect(encoder.started, hasLength(1));
    expect(encoder.started.single.source, VideoCaptureSource.display);
  });

  test('a start the encoder refuses leaves the module free', () async {
    final encoder = FakeVideoEncoder()..startFailure = StateError('no encoder');
    final hub = VideoCaptureHub(encoder: encoder);

    await expectLater(hub.startShare(), throwsStateError);
    expect(hub.isCapturing, isFalse);

    // The failed attempt is not remembered as a running capture, so the next
    // one does not have to fight a phantom.
    encoder.startFailure = null;
    await hub.startShare();
    expect(hub.isCapturing, isTrue);
  });

  test(
    'the settings outlive the capture, because the clip buffer does',
    () async {
      final encoder = FakeVideoEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      final camera = await hub.startCamera();
      await camera.release();

      expect(hub.isCapturing, isFalse);
      expect(hub.settings, hub.cameraSettings);

      // Released again: nothing to stop, and the encoder is not asked twice.
      await camera.release();
      expect(encoder.stopped, 1);
    },
  );

  test('frames and keyframe asks reach whoever attached', () async {
    final encoder = FakeVideoEncoder();
    final hub = VideoCaptureHub(encoder: encoder);
    final frames = <EncodedVideoFrame>[];
    hub.frames.listen(frames.add);

    final share = await hub.startShare();
    encoder.emit();
    await share.requestKeyframe();
    await share.setPaused(paused: true);

    expect(frames, hasLength(1));
    expect(encoder.keyframes, 1);
    expect(encoder.pauses, [true]);
  });

  test('a released lease steers nothing', () async {
    final encoder = FakeVideoEncoder();
    final hub = VideoCaptureHub(encoder: encoder);
    final share = await hub.startShare();
    await share.release();

    await share.requestKeyframe();
    await share.setPaused(paused: true);
    expect(await share.setBitrate(1000000), isFalse);

    expect(encoder.stopped, 1);
    expect(encoder.keyframes, 0);
    expect(encoder.pauses, isEmpty);
    expect(encoder.bitrates, isEmpty);
  });

  test('a stale lease does not touch a newer capture', () async {
    final encoder = FakeVideoEncoder();
    final hub = VideoCaptureHub(encoder: encoder);
    final share = await hub.startShare();
    await share.release();
    final camera = await hub.startCamera();

    // The share's holder, cleaning up late, is holding nothing any more.
    await share.release();
    await share.requestKeyframe();

    expect(encoder.stopped, 1);
    expect(encoder.keyframes, 0);
    expect(hub.isCapturing, isTrue);
    expect(hub.settings, camera.settings);
  });

  group('a quality change while a share runs', () {
    test('a same-shape change sets the bitrate and reports it', () async {
      final encoder = FakeVideoEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      final share = await hub.startShare();
      final reported = <VideoEncoderSettings>[];
      share.settingsChanges.listen(reported.add);

      await hub.setQuality(const StreamQualitySettings(shareBitrate: 3000000));
      await pumpEventQueue();

      expect(encoder.started, hasLength(1));
      expect(encoder.stopped, 0);
      expect(encoder.bitrates, [3000000]);
      expect(share.settings.bitrate, 3000000);
      // The sender's pace follows the number too, so the change is reported.
      expect(reported.single, share.settings);
    });

    test(
      'a new shape restarts the encoder under the same lease and reports it',
      () async {
        final encoder = FakeVideoEncoder();
        final hub = VideoCaptureHub(encoder: encoder);
        final share = await hub.startShare(displayIndex: 1);
        await share.setPaused(paused: true);
        final reported = <VideoEncoderSettings>[];
        share.settingsChanges.listen(reported.add);

        await hub.setQuality(
          const StreamQualitySettings(
            shareResolution: StreamResolution.p1080,
            shareFrameRate: 60,
          ),
        );
        await pumpEventQueue();

        expect(encoder.stopped, 1);
        expect(encoder.started, hasLength(2));
        expect(encoder.started.last.height, 1080);
        expect(encoder.started.last.framesPerSecond, 60);
        // The same display, and still held back: the restart is not a new
        // capture to the holder.
        expect(encoder.started.last.displayIndex, 1);
        expect(encoder.pauses, [true, true]);
        expect(reported.single, encoder.started.last);
        expect(share.settings, encoder.started.last);
        expect(hub.settings, encoder.started.last);

        // The lease is the same one: it still steers, and releases once.
        await share.requestKeyframe();
        expect(encoder.keyframes, 1);
        await share.release();
        expect(encoder.stopped, 2);
        expect(hub.isCapturing, isFalse);
      },
    );

    test('a restart the encoder refuses is reported as an error', () async {
      final encoder = FakeVideoEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      final share = await hub.startShare();
      final errors = <Object>[];
      share.settingsChanges.listen((_) {}, onError: errors.add);

      encoder.startFailure = StateError('no encoder');
      await hub.setQuality(
        const StreamQualitySettings(shareResolution: StreamResolution.p1080),
      );
      await pumpEventQueue();

      expect(errors.single, isA<StateError>());
      expect(share.settings.height, 720);
      // Nothing runs, so nothing is held: a camera can start.
      expect(hub.isCapturing, isFalse);
      encoder.startFailure = null;
      await hub.startCamera();
      expect(encoder.started, hasLength(2));
    });

    test(
      'a release during the restart wins, and nothing is reported',
      () async {
        final encoder = FakeVideoEncoder();
        final hub = VideoCaptureHub(encoder: encoder);
        final share = await hub.startShare();
        final reported = <Object>[];
        share.settingsChanges.listen(reported.add, onError: reported.add);

        encoder.gate = Completer<void>();
        final reshaped = hub.setQuality(
          const StreamQualitySettings(shareResolution: StreamResolution.p1080),
        );
        await pumpEventQueue();
        // The old encoder is stopped and the new one is held mid-open.
        expect(encoder.stopped, 1);
        final released = share.release();
        encoder.gate!.complete();
        await reshaped;
        await released;
        await pumpEventQueue();

        expect(hub.isCapturing, isFalse);
        expect(encoder.stopped, 2);
        expect(reported, isEmpty);
      },
    );

    test('a camera lease ignores quality', () async {
      final encoder = FakeVideoEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      final camera = await hub.startCamera();
      final reported = <VideoEncoderSettings>[];
      camera.settingsChanges.listen(reported.add);

      await hub.setQuality(
        const StreamQualitySettings(
          cameraBitrate: 300000,
          shareResolution: StreamResolution.p1080,
        ),
      );
      await pumpEventQueue();

      expect(encoder.started, hasLength(1));
      expect(encoder.bitrates, isEmpty);
      expect(reported, isEmpty);
    });

    test('a change while nothing runs touches no encoder', () async {
      final encoder = FakeVideoEncoder();
      final hub = VideoCaptureHub(encoder: encoder);

      await hub.setQuality(const StreamQualitySettings(shareBitrate: 3000000));

      expect(encoder.started, isEmpty);
      expect(encoder.bitrates, isEmpty);
    });
  });

  test('a share starts against the native sink, a camera does not', () async {
    final encoder = FakeVideoEncoder();
    final destination = _FakeDestination();
    final hub = VideoCaptureHub(encoder: encoder, shareFrames: destination);
    final frames = <EncodedVideoFrame>[];
    hub.frames.listen(frames.add);

    final share = await hub.startShare();
    // What the isolate sends is echoed back for the clip buffer.
    destination.echo();
    await pumpEventQueue();
    expect(frames, hasLength(1));
    await share.release();

    await hub.startCamera();

    expect(encoder.frameSinks, [_FakeDestination.sink, null]);
  });

  test('a refused bitrate is logged once per lease', () async {
    final encoder = FakeVideoEncoder()..acceptsBitrate = false;
    final lines = <String>[];
    final hub = VideoCaptureHub(encoder: encoder, onDiagnostic: lines.add);

    final share = await hub.startShare();
    expect(await share.setBitrate(2000000), isFalse);
    expect(await share.setBitrate(1500000), isFalse);
    await share.release();
    final again = await hub.startShare();
    await again.setBitrate(1000000);

    expect(encoder.bitrates, [2000000, 1500000, 1000000]);
    expect(lines, hasLength(2));
    expect(lines.first, contains('bitrate'));
    // The encoder kept its rate, and the record says so.
    expect(again.settings.bitrate, 2500000);
  });
}

final class _FakeDestination implements ShareFrameDestination {
  static const sink = 0xf00d;

  final StreamController<EncodedVideoFrame> _echoed =
      StreamController.broadcast();

  void echo() => _echoed.add(
    EncodedVideoFrame(
      bytes: FakeVideoEncoder.keyframeBytes,
      timestamp: Duration.zero,
      isKeyframe: true,
    ),
  );

  @override
  Future<int?> get nativeFrameSink => Future.value(sink);

  @override
  Stream<EncodedVideoFrame> get relayedFrames => _echoed.stream;
}
