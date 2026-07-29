import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flucord/src/data/video/clip_recorder.dart';
import 'package:flucord/src/data/video/native_video_bindings.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the ring buffer', () {
    test('a clip starts on a keyframe, never on a difference', () async {
      final frames = StreamController<EncodedVideoFrame>();
      final recorder = NativeClipRecorder(
        writer: _stubWriter(),
        window: const Duration(seconds: 2),
      );
      addTearDown(recorder.detach);
      recorder.attach(frames.stream, const VideoEncoderSettings());

      // A delta frame before the first keyframe cannot open a clip: the
      // picture it is a difference from was never in the buffer.
      frames
        ..add(_frame(0, isKeyframe: false))
        ..add(_frame(100, isKeyframe: true))
        ..add(_frame(200, isKeyframe: false));
      await Future<void>.delayed(Duration.zero);

      expect(recorder.clipFrames.first.isKeyframe, isTrue);
      expect(recorder.clipFrames.length, 2);
    });

    test('what ages out is dropped, but never the last keyframe', () async {
      final frames = StreamController<EncodedVideoFrame>();
      final recorder = NativeClipRecorder(
        writer: _stubWriter(),
        window: const Duration(seconds: 1),
      );
      addTearDown(recorder.detach);
      recorder.attach(frames.stream, const VideoEncoderSettings());

      frames.add(_frame(0, isKeyframe: true));
      for (var index = 1; index <= 5; index++) {
        frames.add(_frame(index * 1000000, isKeyframe: false));
      }
      await Future<void>.delayed(Duration.zero);

      // Five seconds of deltas past a one-second window, and the keyframe is
      // still held: dropping it would leave a clip nothing can decode.
      expect(recorder.clipFrames.first.isKeyframe, isTrue);
      expect(recorder.buffered, const Duration(seconds: 5));

      frames.add(_frame(6000000, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);
      // Now that a newer keyframe exists, the old front can go.
      expect(recorder.clipFrames.length, lessThan(7));
    });

    test('detaching forgets what was held', () async {
      final frames = StreamController<EncodedVideoFrame>.broadcast();
      final recorder = NativeClipRecorder(writer: _stubWriter());
      recorder.attach(frames.stream, const VideoEncoderSettings());
      frames.add(_frame(0, isKeyframe: true));
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
        ..attach(
          const Stream<EncodedVideoFrame>.empty(),
          const VideoEncoderSettings(),
        )
        ..detach();
      expect((await recorder.save()).failure, ClipFailure.unsupported);
    });

    test('a recorder with no writer refuses before it touches the disk', () async {
      final recorder = NativeClipRecorder(bindings: null, writer: null);

      expect(recorder.isSupported, isFalse);
      expect((await recorder.save()).failure, ClipFailure.unsupported);
    });

    test('an empty buffer is not a failure to write', () async {
      final recorder = NativeClipRecorder(writer: _stubWriter());
      recorder.attach(
        const Stream<EncodedVideoFrame>.empty(),
        const VideoEncoderSettings(),
      );
      addTearDown(recorder.detach);

      expect((await recorder.save()).failure, ClipFailure.empty);
    });

    test('the frames reach the writer with rebased timestamps', () async {
      final calls = <(int, int, bool)>[];
      final frames = StreamController<EncodedVideoFrame>();
      final directory = await Directory.systemTemp.createTemp('flucord-clip');
      addTearDown(() => directory.delete(recursive: true));
      final recorder = NativeClipRecorder(
        writer: _stubWriter(onWrite: calls.add),
        directory: () async => directory,
        now: () => DateTime(2026, 7, 29, 2, 3, 4),
      );
      addTearDown(recorder.detach);
      recorder.attach(frames.stream, const VideoEncoderSettings());
      frames
        ..add(_frame(5000000, isKeyframe: true))
        ..add(_frame(5040000, isKeyframe: false));
      await Future<void>.delayed(Duration.zero);

      final result = await recorder.save();

      expect(result.isSaved, isTrue);
      expect(result.path, endsWith('flucord-clip-20260729-020304.mp4'));
      // The file starts at zero rather than at whenever the encoder happened
      // to have been running since.
      expect(calls.map((call) => call.$2), [0, 40000]);
      expect(calls.first.$3, isTrue);
    });

    test('a writer that refuses a frame is reported, and still closed', () async {
      var closes = 0;
      final frames = StreamController<EncodedVideoFrame>();
      final recorder = NativeClipRecorder(
        writer: _stubWriter(failWrite: true, onClose: () => closes++),
        directory: () async => Directory.systemTemp,
      );
      addTearDown(recorder.detach);
      recorder.attach(frames.stream, const VideoEncoderSettings());
      frames.add(_frame(0, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);

      expect((await recorder.save()).failure, ClipFailure.write);
      // A file left unfinalised is one no player opens.
      expect(closes, 1);
    });

    test('a writer that will not open the file is reported', () async {
      final frames = StreamController<EncodedVideoFrame>();
      final recorder = NativeClipRecorder(
        writer: _stubWriter(failOpen: true),
        directory: () async => Directory.systemTemp,
      );
      addTearDown(recorder.detach);
      recorder.attach(frames.stream, const VideoEncoderSettings());
      frames.add(_frame(0, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);

      expect((await recorder.save()).failure, ClipFailure.write);
    });

    test('a directory that cannot be reached is reported, not thrown', () async {
      final frames = StreamController<EncodedVideoFrame>();
      final recorder = NativeClipRecorder(
        writer: _stubWriter(),
        directory: () async => throw const FileSystemException('nowhere'),
      );
      addTearDown(recorder.detach);
      recorder.attach(frames.stream, const VideoEncoderSettings());
      frames.add(_frame(0, isKeyframe: true));
      await Future<void>.delayed(Duration.zero);

      expect((await recorder.save()).failure, ClipFailure.write);
    });

    test('the name sorts and says when it was taken', () {
      expect(
        NativeClipRecorder.fileNameFor(DateTime(2026, 1, 2, 3, 4, 5)),
        'flucord-clip-20260102-030405.mp4',
      );
    });
  });

  group('against the real module', () {
    test('a clip of encoded frames becomes an MP4 a player would open', () async {
      const path = 'build/windows/x64/runner/Release/flucord_video.dll';
      if (!Platform.isWindows || !File(path).existsSync()) return;
      final bindings = NativeVideoBindings(DynamicLibrary.open(path));
      expect(bindings.clip, isNotNull);

      // Real H.264 rather than made-up bytes: the file sink parses what it is
      // handed, and a stub would prove only that the call returned.
      final encoded = <EncodedVideoFrame>[];
      if (!await _encodeSomething(bindings, encoded)) return;

      final directory = await Directory.systemTemp.createTemp('flucord-clip');
      addTearDown(() => directory.delete(recursive: true));
      final frames = StreamController<EncodedVideoFrame>();
      final recorder = NativeClipRecorder(
        bindings: bindings,
        directory: () async => directory,
        now: () => DateTime(2026, 7, 29, 5, 6, 7),
      );
      addTearDown(recorder.detach);
      recorder.attach(
        frames.stream,
        const VideoEncoderSettings(width: 640, height: 360, framesPerSecond: 15),
      );
      for (final frame in encoded) {
        frames.add(frame);
      }
      await Future<void>.delayed(Duration.zero);

      final result = await recorder.save();
      expect(result.isSaved, isTrue);
      final bytes = File(result.path!).readAsBytesSync();
      // 'ftyp' at offset four is what makes it an MP4 rather than a file with
      // an MP4 name on it.
      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
      expect(bytes.length, greaterThan(1000));
    });
  });
}

/// Runs the real encoder briefly, so the muxer is handed frames it produced.
///
/// Answers false where there is no display to capture, which is what lets the
/// test above skip itself on a machine that has none.
Future<bool> _encodeSomething(
  NativeVideoBindings bindings,
  List<EncodedVideoFrame> into,
) async {
  final config = calloc<NativeVideoConfig>();
  final out = calloc<Pointer<Void>>();
  final done = Completer<void>();
  final callback = NativeCallable<NativeFrameCallback>.listener((
    Pointer<Void> userData,
    Pointer<Uint8> data,
    int length,
    int timestampUs,
    int isKeyframe,
  ) {
    if (length > 0) {
      into.add(
        EncodedVideoFrame(
          bytes: Uint8List.fromList(data.asTypedList(length)),
          timestamp: Duration(microseconds: timestampUs),
          isKeyframe: isKeyframe != 0,
        ),
      );
    }
    bindings.releaseFrame(data);
    if (into.length >= 8 && !done.isCompleted) done.complete();
  });
  try {
    config.ref
      ..displayIndex = 0
      ..width = 640
      ..height = 360
      ..framesPerSecond = 15
      ..bitrate = 800000;
    if (bindings.open(config, callback.nativeFunction, nullptr, out) != 0) {
      return false;
    }
    await Future.any([
      done.future,
      Future<void>.delayed(const Duration(seconds: 4)),
    ]);
    bindings.close(out.value);
    return into.any((frame) => frame.isKeyframe);
  } finally {
    callback.close();
    calloc
      ..free(config)
      ..free(out);
  }
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
