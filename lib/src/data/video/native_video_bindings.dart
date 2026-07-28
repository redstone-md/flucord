import 'dart:ffi';

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
      displayCount = library.lookupFunction<Int32 Function(), int Function()>(
        'flucord_video_display_count',
      );

  final VideoOpenDart open;
  final int Function(Pointer<Void>) requestKeyframe;
  final int Function(Pointer<Void>, int) setPaused;
  final void Function(Pointer<Void>) close;
  final void Function(Pointer<Uint8>) releaseFrame;
  final int Function() displayCount;
}

/// `FlucordVideoStatus`.
abstract final class NativeVideoStatus {
  static const ok = 0;
  static const unsupported = 1;
  static const noDisplay = 2;
  static const encoder = 3;
  static const state = 4;
}
