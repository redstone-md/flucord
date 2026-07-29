import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flucord/src/data/video/native_video_bindings.dart';
import 'package:flucord/src/data/video/screenshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what comes off the GPU', () {
    test('row padding is removed before anything encodes it', () {
      // A GPU pads rows: a picture encoded from the padded buffer shears
      // further with every line.
      final screen = CapturedScreen(
        pixels: Uint8List.fromList([
          1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0,
          9, 10, 11, 12, 13, 14, 15, 16, 0, 0, 0, 0,
        ]),
        width: 2,
        height: 2,
        stride: 12,
      );

      expect(screen.packed, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
    });

    test('an unpadded frame is handed through untouched', () {
      final pixels = Uint8List.fromList(List<int>.filled(16, 7));
      final screen = CapturedScreen(
        pixels: pixels,
        width: 2,
        height: 2,
        stride: 8,
      );

      expect(identical(screen.packed, pixels), isTrue);
    });

    test('a captured frame encodes as a real PNG', () async {
      final png = await NativeScreenshotService.encodePng(
        CapturedScreen(
          pixels: Uint8List(4 * 4),
          width: 2,
          height: 2,
          stride: 8,
        ),
      );

      expect(png, isNotNull);
      // The PNG signature, so this is an encoder's output rather than the
      // pixels handed back.
      expect(png!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  });

  group('where it is written', () {
    test('the name sorts and says when it was taken', () {
      expect(
        NativeScreenshotService.fileNameFor(DateTime(2026, 7, 29, 4, 5, 6)),
        'flucord-20260729-040506.png',
      );
    });

    test('a build with no capture answers unsupported', () async {
      const service = UnavailableScreenshotService();

      expect(service.isSupported, isFalse);
      final result = await service.save();
      expect(result.isSaved, isFalse);
      expect(result.failure, ScreenshotFailure.unsupported);
    });

    test('a native service with no module says the same', () async {
      final service = NativeScreenshotService(bindings: null);

      expect(service.isSupported, isFalse);
      expect(service.capture(), isNull);
      expect((await service.save()).failure, ScreenshotFailure.unsupported);
    });


    test('a captured screen is written as a PNG where it says', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-shot');
      addTearDown(() => directory.delete(recursive: true));
      final service = NativeScreenshotService(
        captureScreen: _stubCapture(width: 2, height: 2),
        directory: () async => directory,
        now: () => DateTime(2026, 7, 29, 1, 2, 3),
      );

      expect(service.isSupported, isTrue);
      final result = await service.save();

      expect(result.isSaved, isTrue);
      expect(result.path, endsWith('flucord-20260729-010203.png'));
      final written = File(result.path!).readAsBytesSync();
      expect(written.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });


    test('with no directory given it reaches for the documents folder',
        () async {
      // No plugin answers in a test, so the reach fails and is reported —
      // which is also what a machine with an unwritable profile would do.
      final service = NativeScreenshotService(
        captureScreen: _stubCapture(width: 2, height: 2),
      );

      final result = await service.save();

      expect(result.isSaved, isFalse);
      expect(result.failure, ScreenshotFailure.write);
    });

    test('a capture the native side refuses is reported', () async {
      final service = NativeScreenshotService(
        captureScreen: (index, callback, userData) => 2,
      );

      expect((await service.save()).failure, ScreenshotFailure.unsupported);
    });

    test('a frame with no pixels in it is not written as one', () async {
      final service = NativeScreenshotService(
        captureScreen: _stubCapture(width: 0, height: 0),
      );

      // The callback ran and described nothing, which is not a picture.
      expect(service.capture(), isNull);
      expect((await service.save()).failure, ScreenshotFailure.unsupported);
    });

    test('a directory that cannot be created is reported, not thrown',
        () async {
      final service = NativeScreenshotService(
        captureScreen: _stubCapture(width: 2, height: 2),
        directory: () async => throw const FileSystemException('nowhere'),
      );

      final result = await service.save();

      expect(result.isSaved, isFalse);
      expect(result.failure, ScreenshotFailure.write);
    });

    test('a real capture is written where it says it was', () async {
      const path = 'build/windows/x64/runner/Release/flucord_video.dll';
      if (!Platform.isWindows || !File(path).existsSync()) return;
      final directory = await Directory.systemTemp.createTemp('flucord-shot');
      addTearDown(() => directory.delete(recursive: true));
      final service = NativeScreenshotService(
        bindings: NativeVideoBindings(DynamicLibrary.open(path)),
        directory: () async => directory,
        now: () => DateTime(2026, 7, 29, 1, 2, 3),
      );

      expect(service.isSupported, isTrue);
      final result = await service.save();

      // A machine with no display attached cannot produce one, and says so
      // rather than writing an empty file.
      if (!result.isSaved) {
        expect(result.failure, ScreenshotFailure.unsupported);
        return;
      }
      final file = File(result.path!);
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync().take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(result.path, endsWith('flucord-20260729-010203.png'));
    });

    test('a directory that cannot be written is reported, not thrown',
        () async {
      const path = 'build/windows/x64/runner/Release/flucord_video.dll';
      if (!Platform.isWindows || !File(path).existsSync()) return;
      final service = NativeScreenshotService(
        bindings: NativeVideoBindings(DynamicLibrary.open(path)),
        directory: () async => throw const FileSystemException('no directory'),
      );

      final result = await service.save();
      expect(result.isSaved, isFalse);
      expect(
        result.failure,
        anyOf(ScreenshotFailure.write, ScreenshotFailure.unsupported),
      );
    });
  });
}


/// Stands in for `flucord_video_capture_screen`, calling the native callback
/// the way the module does — through the pointer it was handed.
ScreenshotCaptureDart _stubCapture({required int width, required int height}) =>
    (index, callback, userData) {
      final stride = width * 4;
      final pixels = calloc<Uint8>(stride * height == 0 ? 1 : stride * height);
      try {
        callback
            .asFunction<
              void Function(Pointer<Void>, Pointer<Uint8>, int, int, int)
            >()(userData, pixels, width, height, stride);
      } finally {
        calloc.free(pixels);
      }
      return 0;
    };
