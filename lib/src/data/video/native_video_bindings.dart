import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `FlucordVideoConfig`, laid out to match the header.
final class NativeVideoConfig extends Struct {
  @Int32()
  external int displayIndex;

  @Int32()
  external int width;

  @Int32()
  external int height;

  @Int32()
  external int framesPerSecond;

  @Int32()
  external int bitrate;
}

typedef NativeFrameCallback =
    Void Function(Pointer<Void>, Pointer<Uint8>, Int32, Int64, Int32);

typedef NativePictureCallback =
    Void Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32, Int32, Int64);

typedef _DecoderOpenNative =
    Int32 Function(
      Pointer<NativeFunction<NativePictureCallback>>,
      Pointer<Void>,
      Pointer<Pointer<Void>>,
    );

typedef VideoDecoderOpenDart =
    int Function(
      Pointer<NativeFunction<NativePictureCallback>>,
      Pointer<Void>,
      Pointer<Pointer<Void>>,
    );

typedef _DecoderSubmitNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Int64);

typedef VideoDecoderSubmitDart =
    int Function(Pointer<Void>, Pointer<Uint8>, int, int);

typedef VideoOpenNative =
    Int32 Function(
      Pointer<NativeVideoConfig>,
      Pointer<NativeFunction<NativeFrameCallback>>,
      Pointer<Void>,
      Pointer<Pointer<Void>>,
    );

typedef VideoOpenDart =
    int Function(
      Pointer<NativeVideoConfig>,
      Pointer<NativeFunction<NativeFrameCallback>>,
      Pointer<Void>,
      Pointer<Pointer<Void>>,
    );

/// The five functions `flucord_video.dll` exports.
///
/// Split from the service so the Dart half can be tested against a stand-in:
/// the encoder needs a display and a GPU, and neither exists on a test host.
final class NativeVideoBindings {
  NativeVideoBindings(DynamicLibrary library)
    : open = library.lookupFunction<VideoOpenNative, VideoOpenDart>(
        'flucord_video_open',
      ),
      requestKeyframe = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('flucord_video_request_keyframe'),
      setPaused = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('flucord_video_set_paused'),
      close = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('flucord_video_close'),
      releaseFrame = library
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('flucord_video_release_frame'),
      decodeProbe = library
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Int32),
            int Function(Pointer<Uint8>, int)
          >('flucord_video_decode_probe'),
      decoderOpen = library
          .lookupFunction<_DecoderOpenNative, VideoDecoderOpenDart>(
            'flucord_video_decoder_open',
          ),
      decoderSubmit = library
          .lookupFunction<_DecoderSubmitNative, VideoDecoderSubmitDart>(
            'flucord_video_decoder_submit',
          ),
      decoderClose = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('flucord_video_decoder_close'),
      displayCount = library.lookupFunction<Int32 Function(), int Function()>(
        'flucord_video_display_count',
      ),
      openCamera = library.lookupFunction<VideoOpenNative, VideoOpenDart>(
        'flucord_video_open_camera',
      ),
      cameraCount = library.lookupFunction<Int32 Function(), int Function()>(
        'flucord_video_camera_count',
      ),
      cameraName = library
          .lookupFunction<
            Int32 Function(Int32, Pointer<Utf8>, Int32),
            int Function(int, Pointer<Utf8>, int)
          >('flucord_video_camera_name'),
      captureScreen = _lookUpCaptureScreen(library),
      lastError = _lookUpLastError(library),
      clip = ClipWriterBindings.lookUp(library);

  /// The platform's own answer behind the last failure, where the module
  /// reports one. Absent in a module built before it did.
  static int Function()? _lookUpLastError(DynamicLibrary library) {
    try {
      return library.lookupFunction<Int32 Function(), int Function()>(
        'flucord_video_last_error',
      );
    } on Object {
      return null;
    }
  }

  /// Absent in a module built before screenshots existed, which is a build
  /// that must still run rather than fail to load.
  static ScreenshotCaptureDart? _lookUpCaptureScreen(DynamicLibrary library) {
    try {
      return library
          .lookupFunction<ScreenshotCaptureNative, ScreenshotCaptureDart>(
            'flucord_video_capture_screen',
          );
    } on Object {
      return null;
    }
  }

  final VideoOpenDart open;
  final int Function(Pointer<Void>) requestKeyframe;
  final int Function(Pointer<Void>, int) setPaused;
  final void Function(Pointer<Void>) close;
  final void Function(Pointer<Uint8>) releaseFrame;

  /// Runs an Annex B stream through the system decoder; returns the picture
  /// count, or a negative status.
  final int Function(Pointer<Uint8>, int) decodeProbe;

  /// Opens a decoder for somebody else's stream.
  final VideoDecoderOpenDart decoderOpen;
  final VideoDecoderSubmitDart decoderSubmit;
  final void Function(Pointer<Void>) decoderClose;
  final int Function() displayCount;

  /// The same pipeline, reading a camera instead of a display.
  final VideoOpenDart openCamera;
  final int Function() cameraCount;

  /// Writes a camera's UTF-8 name into the buffer and answers how many bytes
  /// it needed; a capacity of zero asks the length without writing.
  final int Function(int, Pointer<Utf8>, int) cameraName;

  /// One BGRA frame from a display, or null in a module without it.
  final ScreenshotCaptureDart? captureScreen;

  /// Reads the HRESULT behind the last failure, when the module reports one.
  final int Function()? lastError;

  /// The MP4 writer, or null in a module built before clips existed.
  final ClipWriterBindings? clip;
}

/// The three calls that turn encoded frames into a file.
final class ClipWriterBindings {
  const ClipWriterBindings({
    required this.open,
    required this.write,
    required this.close,
  });

  /// Looked up together: a module with one of them has all three, and one
  /// with none is simply older than the feature.
  static ClipWriterBindings? lookUp(DynamicLibrary library) {
    try {
      return ClipWriterBindings(
        open: library.lookupFunction<ClipOpenNative, ClipOpenDart>(
          'flucord_video_clip_open',
        ),
        write: library.lookupFunction<ClipWriteNative, ClipWriteDart>(
          'flucord_video_clip_write',
        ),
        close: library
            .lookupFunction<
              Int32 Function(Pointer<Void>),
              int Function(Pointer<Void>)
            >('flucord_video_clip_close'),
      );
    } on Object {
      return null;
    }
  }

  final ClipOpenDart open;
  final ClipWriteDart write;
  final int Function(Pointer<Void>) close;
}

typedef ClipOpenNative =
    Int32 Function(
      Pointer<Utf8>,
      Int32,
      Int32,
      Int32,
      Int32,
      Pointer<Pointer<Void>>,
    );

typedef ClipOpenDart =
    int Function(Pointer<Utf8>, int, int, int, int, Pointer<Pointer<Void>>);

typedef ClipWriteNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Int64, Int32);

typedef ClipWriteDart =
    int Function(Pointer<Void>, Pointer<Uint8>, int, int, int);

typedef NativeScreenshotCallback =
    Void Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32, Int32);

typedef ScreenshotCaptureNative =
    Int32 Function(
      Int32,
      Pointer<NativeFunction<NativeScreenshotCallback>>,
      Pointer<Void>,
    );

typedef ScreenshotCaptureDart =
    int Function(
      int,
      Pointer<NativeFunction<NativeScreenshotCallback>>,
      Pointer<Void>,
    );

/// `FlucordVideoStatus`.
abstract final class NativeVideoStatus {
  static const ok = 0;
  static const unsupported = 1;
  static const noDisplay = 2;
  static const encoder = 3;
  static const state = 4;
  static const noCamera = 5;
}
