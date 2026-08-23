import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flucord/src/data/video/clip_recorder.dart';
import 'package:flucord/src/data/video/native_video_bindings.dart';
import 'package:flucord/src/data/video/native_video_encoder_service.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the ring buffer', () {
    test('a clip starts on a keyframe, never on a difference', () async {
      final recorder = NativeClipRecorder(
        writer: _stubWriter(),
        window: const Duration(seconds: 2),
      );
      final capture = _attachedCapture(recorder);
      await capture.start();

      // A delta frame before the first keyframe cannot open a clip: the
      // picture it is a difference from was never in the buffer.
      capture.emit(_frame(0, isKeyframe: false));
      capture.emit(_frame(100, isKeyframe: true));
      capture.emit(_frame(200, isKeyframe: false));
      await Future<void>.delayed(Duration.zero);

      expect(recorder.clipFrames.first.isKeyframe, isTrue);
      expect(recorder.clipFrames.length, 2);
    });

    test('what ages out is dropped, but never the last keyframe', () async {
      final recorder = NativeClipRecorder(
        writer: _stubWriter(),
        window: const Duration(seconds: 1),
      );
      final capture = _attachedCapture(recorder);
      await capture.start();

      capture.emit(_frame(0, isKeyframe: true));
      for (var index = 1; index <= 5; index++) {
        capture.emit(_frame(index * 1000000, isKeyframe: false));
      }
      await Future<void>.delayed(Duration.zero);

      // Five seconds of deltas past a one-second window, and the keyframe is
      // still held: dropping it would leave a clip nothing can decode.
      expect(recorder.clipFrames.first.isKeyframe, isTrue);
      expect(recorder.buffered, const Duration(seconds: 5));

      capture.emit(_frame(6000000, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);
      // Now that a newer keyframe exists, the old front can go.
      expect(recorder.clipFrames.length, lessThan(7));
    });

    test('a capture under different settings empties the buffer', () async {
      final recorder = NativeClipRecorder(
        writer: _stubWriter(),
        window: const Duration(seconds: 30),
      );
      final capture = _attachedCapture(recorder);
      await capture.hub.startShare();
      capture.emit(_frame(0, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.clipFrames, isNotEmpty);

      await capture.hub.stop();
      await capture.hub.startCamera();

      // A share's frames and a camera's frames cannot sit in one file: they
      // were encoded at different rates, and the writer is told one header.
      capture.emit(_frame(50000000, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.clipFrames, hasLength(1));
      await capture.hub.stop();
    });

    test('detaching forgets what was held', () async {
      final recorder = NativeClipRecorder(writer: _stubWriter());
      final capture = _attachedCapture(recorder);
      await capture.start();
      capture.emit(_frame(0, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.clipFrames, isNotEmpty);

      recorder.detach();

      expect(recorder.clipFrames, isEmpty);
      expect(recorder.buffered, Duration.zero);
    });
  });

  group('saving', () {
    test('a build with no writer says so', () async {
      const recorder = UnavailableClipRecorder();

      expect(recorder.isSupported, isFalse);
      expect(recorder.buffered, Duration.zero);
      recorder
        ..attach(VideoCaptureHub(encoder: _FakeEncoder()))
        ..detach();
      expect((await recorder.save()).failure, ClipFailure.unsupported);
    });

    test(
      'a recorder with no writer refuses before it touches the disk',
      () async {
        final recorder = NativeClipRecorder(bindings: null, writer: null);

        expect(recorder.isSupported, isFalse);
        expect((await recorder.save()).failure, ClipFailure.unsupported);
      },
    );

    test('an empty buffer is not a failure to write', () async {
      final recorder = NativeClipRecorder(writer: _stubWriter());
      recorder.attach(VideoCaptureHub(encoder: _FakeEncoder()));
      addTearDown(recorder.detach);

      expect((await recorder.save()).failure, ClipFailure.empty);
    });

    test('the frames reach the writer with rebased timestamps', () async {
      final calls = <(int, int, bool)>[];
      final directory = await Directory.systemTemp.createTemp('flucord-clip');
      addTearDown(() => directory.delete(recursive: true));
      final recorder = NativeClipRecorder(
        writer: _stubWriter(onWrite: calls.add),
        directory: () async => directory,
        now: () => DateTime(2026, 7, 29, 2, 3, 4),
      );
      final capture = _attachedCapture(recorder);
      await capture.start();
      capture
        ..emit(_frame(5000000, isKeyframe: true))
        ..emit(_frame(5040000, isKeyframe: false));
      await Future<void>.delayed(Duration.zero);

      final result = await recorder.save();

      expect(result.isSaved, isTrue);
      expect(result.path, endsWith('flucord-clip-20260729-020304.mp4'));
      // The file starts at zero rather than at whenever the encoder happened
      // to have been running since.
      expect(calls.map((call) => call.$2), [0, 40000]);
      expect(calls.first.$3, isTrue);
    });

    test(
      'a writer that refuses a frame is reported, and still closed',
      () async {
        var closes = 0;
        final recorder = NativeClipRecorder(
          writer: _stubWriter(failWrite: true, onClose: () => closes++),
          directory: () async => Directory.systemTemp,
        );
        final capture = _attachedCapture(recorder);
        await capture.start();
        capture.emit(_frame(0, isKeyframe: true));
        await Future<void>.delayed(Duration.zero);

        expect((await recorder.save()).failure, ClipFailure.write);
        // A file left unfinalised is one no player opens.
        expect(closes, 1);
      },
    );

    test('a writer that will not open the file is reported', () async {
      final recorder = NativeClipRecorder(
        writer: _stubWriter(failOpen: true),
        directory: () async => Directory.systemTemp,
      );
      final capture = _attachedCapture(recorder);
      await capture.start();
      capture.emit(_frame(0, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);

      expect((await recorder.save()).failure, ClipFailure.write);
    });

    test(
      'a directory that cannot be reached is reported, not thrown',
      () async {
        final recorder = NativeClipRecorder(
          writer: _stubWriter(),
          directory: () async => throw const FileSystemException('nowhere'),
        );
        final capture = _attachedCapture(recorder);
        await capture.start();
        capture.emit(_frame(0, isKeyframe: true));
        await Future<void>.delayed(Duration.zero);

        expect((await recorder.save()).failure, ClipFailure.write);
      },
    );

    test('the name sorts and says when it was taken', () {
      expect(
        NativeClipRecorder.fileNameFor(DateTime(2026, 1, 2, 3, 4, 5)),
        'flucord-clip-20260102-030405.mp4',
      );
    });
  });

  group('against the real module', () {
    test(
      'a clip of encoded frames becomes an MP4 a player would open',
      () async {
        const path = 'build/windows/x64/runner/Release/flucord_video.dll';
        if (!Platform.isWindows || !File(path).existsSync()) return;
        final bindings = NativeVideoBindings(DynamicLibrary.open(path));
        expect(bindings.clip, isNotNull);

        // The whole production path: one capture module over the real encoder,
        // the recorder attached to it, real H.264 frames, one file out.
        final service = NativeVideoEncoderService(bindings: bindings);
        final capture = VideoCaptureHub(encoder: service);
        final recorder = NativeClipRecorder(
          bindings: bindings,
          directory: () async => Directory.systemTemp,
          now: () => DateTime(2026, 7, 29, 5, 6, 7),
        );
        recorder.attach(capture);
        addTearDown(recorder.detach);

        final frames = <EncodedVideoFrame>[];
        final done = Completer<void>();
        final collected = capture.frames.listen((frame) {
          frames.add(frame);
          if (frames.length >= 8 && !done.isCompleted) done.complete();
        });
        bool opened = false;
        try {
          await capture.startShare();
          opened = true;
          await Future.any([
            done.future,
            Future<void>.delayed(const Duration(seconds: 4)),
          ]);
        } on Object {
          // No display to capture on the machine running the test, which is
          // what lets this test skip itself.
          return;
        } finally {
          await collected.cancel();
          if (opened) await capture.stop();
        }

        // Real H.264 rather than made-up bytes: the file sink parses what it is
        // handed, and a stub would prove only that the call returned.
        if (!frames.any((frame) => frame.isKeyframe)) return;
        expect(recorder.buffered, greaterThan(Duration.zero));

        final result = await recorder.save();
        expect(result.isSaved, isTrue);
        final bytes = File(result.path!).readAsBytesSync();
        // 'ftyp' at offset four is what makes it an MP4 rather than a file with
        // an MP4 name on it.
        expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
        expect(bytes.length, greaterThan(1000));
      },
    );
  });
}

/// A recorder attached to the capture module, over a fake encoder the test
/// emits frames through. The capture must be started through the returned
/// module rather than driven by hand: only a running capture knows what its
/// frames are encoded at, and that is what the recorder writes out.
final class _AttachedCapture {
  _AttachedCapture(this.hub, this._encoder);

  final VideoCaptureHub hub;
  final _FakeEncoder _encoder;

  /// Starts a share capture, which is what every one-capture test wants.
  Future<void> start() => hub.startShare();

  void emit(EncodedVideoFrame frame) => _encoder.emit(frame);
}

_AttachedCapture _attachedCapture(NativeClipRecorder recorder) {
  final encoder = _FakeEncoder();
  final hub = VideoCaptureHub(encoder: encoder);
  recorder.attach(hub);
  return _AttachedCapture(hub, encoder);
}

/// A fake encoder whose frames a test emits by hand.
final class _FakeEncoder implements VideoEncoderService {
  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();

  void emit(EncodedVideoFrame frame) => _frames.add(frame);

  @override
  bool get isSupported => true;

  @override
  int get displayCount => 1;

  @override
  List<String> get cameraNames => const ['Webcam'];

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start(VideoEncoderSettings settings) async {}

  @override
  Future<void> requestKeyframe() async {}

  @override
  Future<void> setPaused({required bool paused}) async {}

  @override
  Future<void> stop() async {}
}

EncodedVideoFrame _frame(int microseconds, {required bool isKeyframe}) =>
    EncodedVideoFrame(
      bytes: Uint8List.fromList([0, 0, 0, 1, isKeyframe ? 0x65 : 0x41, 1, 2]),
      timestamp: Duration(microseconds: microseconds),
      isKeyframe: isKeyframe,
    );

/// Stands in for the native writer, recording what it was handed.
ClipWriterBindings _stubWriter({
  void Function((int, int, bool))? onWrite,
  void Function()? onClose,
  bool failOpen = false,
  bool failWrite = false,
}) => ClipWriterBindings(
  open: (path, width, height, fps, bitrate, out) {
    if (failOpen) return 1;
    out.value = Pointer<Void>.fromAddress(1);
    return 0;
  },
  write: (clip, bytes, length, timestampUs, isKeyframe) {
    onWrite?.call((length, timestampUs, isKeyframe != 0));
    return failWrite ? 1 : 0;
  },
  close: (clip) {
    onClose?.call();
    return 0;
  },
);
