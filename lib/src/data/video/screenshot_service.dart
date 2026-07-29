import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import 'native_video_bindings.dart';

/// Where a saved screenshot ended up, or why it did not.
final class ScreenshotResult {
  const ScreenshotResult.saved(this.path)
    : failure = null,
      assert(path != null, 'A saved screenshot has a path');
  const ScreenshotResult.failed(this.failure) : path = null;

  final String? path;
  final ScreenshotFailure? failure;

  bool get isSaved => path != null;
}

enum ScreenshotFailure {
  /// No native module, or no display to read.
  unsupported,

  /// The capture worked and the file did not.
  write,
}

/// Saves a picture of the screen.
///
/// Discord's `SAVE_SCREENSHOT` keybind, which its own client answers with the
/// same capture path its screen share uses — as this does. The picture is
/// encoded here rather than natively: Flutter already has a PNG encoder, and
/// a second one in C++ would be a second thing to get wrong.
abstract interface class ScreenshotService {
  bool get isSupported;

  /// Captures [displayIndex] and writes it to disk, answering where.
  Future<ScreenshotResult> save({int displayIndex = 0});
}

/// A service on a build without the native module. Never pretends.
final class UnavailableScreenshotService implements ScreenshotService {
  const UnavailableScreenshotService();

  @override
  bool get isSupported => false;

  @override
  Future<ScreenshotResult> save({int displayIndex = 0}) async =>
      const ScreenshotResult.failed(ScreenshotFailure.unsupported);
}

typedef _ShotCallback =
    Void Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32, Int32);

/// Desktop Duplication for the pixels, Flutter for the PNG.
final class NativeScreenshotService implements ScreenshotService {
  NativeScreenshotService({
    NativeVideoBindings? bindings,
    ScreenshotCaptureDart? captureScreen,
    Future<Directory> Function()? directory,
    DateTime Function()? now,
  }) : _captureScreen =
           captureScreen ?? (bindings ?? _openLibrary())?.captureScreen,
       _directory = directory ?? _pictures,
       _now = now ?? DateTime.now;

  static NativeVideoBindings? _openLibrary() {
    if (!Platform.isWindows) return null;
    try {
      return NativeVideoBindings(DynamicLibrary.open('flucord_video.dll'));
    } on Object {
      return null;
    }
  }

  /// Pictures, with the client's own folder inside it — which is where
  /// somebody looks for a screenshot without being told.
  static Future<Directory> _pictures() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}'
          '${Platform.pathSeparator}Flucord');

  /// The native entry point, or a stand-in. Held as the function rather than
  /// the whole binding table so a test can drive the capture path without a
  /// display attached to the machine running it.
  final ScreenshotCaptureDart? _captureScreen;
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;

  @override
  bool get isSupported => _captureScreen != null;

  @override
  Future<ScreenshotResult> save({int displayIndex = 0}) async {
    final pixels = capture(displayIndex: displayIndex);
    if (pixels == null) {
      return const ScreenshotResult.failed(ScreenshotFailure.unsupported);
    }
    try {
      final png = await encodePng(pixels);
      if (png == null) {
        return const ScreenshotResult.failed(ScreenshotFailure.write);
      }
      final directory = await _directory();
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}${Platform.pathSeparator}${fileNameFor(_now())}',
      );
      await file.writeAsBytes(png);
      return ScreenshotResult.saved(file.path);
    } on Object {
      return const ScreenshotResult.failed(ScreenshotFailure.write);
    }
  }

  /// The raw frame, or null when nothing could be captured.
  CapturedScreen? capture({int displayIndex = 0}) {
    final captureScreen = _captureScreen;
    if (captureScreen == null) return null;
    CapturedScreen? captured;
    final callback = NativeCallable<_ShotCallback>.isolateLocal((
      Pointer<Void> userData,
      Pointer<Uint8> bgra,
      int width,
      int height,
      int stride,
    ) {
      if (width <= 0 || height <= 0) return;
      // Copied inside the callback: the staging texture is unmapped the
      // moment it returns, and the pointer with it.
      captured = CapturedScreen(
        pixels: Uint8List.fromList(bgra.asTypedList(stride * height)),
        width: width,
        height: height,
        stride: stride,
      );
    });
    try {
      if (captureScreen(displayIndex, callback.nativeFunction, nullptr) != 0) {
        return null;
      }
    } finally {
      callback.close();
    }
    return captured;
  }

  /// Encodes a captured frame as PNG.
  static Future<Uint8List?> encodePng(CapturedScreen screen) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      screen.packed,
      screen.width,
      screen.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    final image = await completer.future;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// The file name a screenshot is saved under.
  ///
  /// Sortable and second-resolution, which is what makes a folder of them
  /// readable; two in the same second overwrite, and that is the same thing
  /// the desktop client does.
  static String fileNameFor(DateTime when) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'flucord-${when.year}${two(when.month)}${two(when.day)}'
        '-${two(when.hour)}${two(when.minute)}${two(when.second)}.png';
  }
}

/// One captured frame, still in the row layout the GPU handed over.
final class CapturedScreen {
  const CapturedScreen({
    required this.pixels,
    required this.width,
    required this.height,
    required this.stride,
  });

  final Uint8List pixels;
  final int width;
  final int height;

  /// Bytes per row, which is not width * 4: the GPU pads rows, and an encoder
  /// handed the padded buffer draws a picture that shears further with every
  /// line.
  final int stride;

  /// The pixels with the row padding removed.
  Uint8List get packed {
    final packedStride = width * 4;
    if (stride == packedStride) return pixels;
    final out = Uint8List(packedStride * height);
    for (var row = 0; row < height; row++) {
      out.setRange(
        row * packedStride,
        (row + 1) * packedStride,
        pixels,
        row * stride,
      );
    }
    return out;
  }
}
