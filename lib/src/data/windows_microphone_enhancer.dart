import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../domain/voice_processing.dart';

/// Echo cancellation and gain control through `flucord_audio.dll`, which
/// runs the Windows voice capture stages on the frames handed to it.
///
/// The stages work one frame behind the microphone, so the enhanced answer
/// for a frame arrives with the next ones and the first few frames of a
/// session pass through as captured while their buffers fill. The work
/// happens on the caller's turn, like the encoder's does.
final class WindowsMicrophoneEnhancer implements VoiceMicrophoneEnhancer {
  /// The factory the composition root offers: null where the bundle has no
  /// native module, so the switches are hidden rather than offered empty.
  /// Probed once here rather than per switch, the way the noise filter's own
  /// factory is.
  static Future<VoiceMicrophoneEnhancer> Function({
    required bool echoCancellation,
    required bool automaticGainControl,
  })?
  bundledFactory() {
    if (!Platform.isWindows) return null;
    try {
      DynamicLibrary.open(libraryFileName);
    } on Object {
      return null;
    }
    return open;
  }

  static const String libraryFileName = 'flucord_audio.dll';

  /// Opens the machine's echo and gain stages. Throws when they cannot be
  /// reached: the pipeline reports the failure and turns both switches
  /// off with it, which is what the settings surface then shows.
  static Future<VoiceMicrophoneEnhancer> open({
    required bool echoCancellation,
    required bool automaticGainControl,
  }) async => WindowsMicrophoneEnhancer(
    DynamicLibrary.open(libraryFileName),
    echoCancellation: echoCancellation,
    automaticGainControl: automaticGainControl,
  );

  WindowsMicrophoneEnhancer._(
    DynamicLibrary library, {
    required this.echoCancellation,
    required this.automaticGainControl,
  }) : _open = library.lookupFunction<_OpenEnhancerNative, _OpenEnhancer>(
         'flucord_audio_open_mic_enhancer',
       ),
       _enhance = library.lookupFunction<_EnhanceFrameNative, _EnhanceFrame>(
         'flucord_audio_enhance_frame',
       ),
       _close = library.lookupFunction<_CloseEnhancerNative, _CloseEnhancer>(
         'flucord_audio_close_mic_enhancer',
       );

  /// The module handed in rather than opened, so a test can drive the
  /// real thing against a build it controls.
  WindowsMicrophoneEnhancer(
    DynamicLibrary library, {
    required bool echoCancellation,
    required bool automaticGainControl,
  }) : this._(
         library,
         echoCancellation: echoCancellation,
         automaticGainControl: automaticGainControl,
       );

  /// Whether the machine's speaker line is taken out of the microphone.
  final bool echoCancellation;

  /// Whether the microphone's level is kept steady.
  final bool automaticGainControl;

  final _OpenEnhancer _open;
  final _EnhanceFrame _enhance;
  final _CloseEnhancer _close;

  Pointer<Void>? _enhancer;
  Pointer<Int16>? _scratch;
  int _scratchSamples = 0;
  bool _disposed = false;

  @override
  Future<void> process(Int16List frame, {required int channels}) async {
    if (_disposed) throw StateError('The enhancer is disposed');
    if (frame.isEmpty || channels <= 0) return;
    final enhancer = _ensureOpen();
    final samples = frame.length ~/ channels;
    // The frame is copied in and the answer copied back out: the stages work
    // on native memory of their own, and the frame handed around the
    // pipeline belongs to the pipeline.
    final scratch = _scratchFor(frame.length);
    scratch.asTypedList(frame.length).setAll(0, frame);
    final status = _enhance(enhancer, scratch, samples, channels);
    if (status != 0) {
      throw StateError('The echo and gain stages failed on a frame');
    }
    frame.setAll(0, scratch.asTypedList(frame.length));
  }

  Pointer<Void> _ensureOpen() {
    final held = _enhancer;
    if (held != null) return held;
    final out = calloc<Pointer<Void>>();
    try {
      final status = _open(
        echoCancellation ? 1 : 0,
        automaticGainControl ? 1 : 0,
        out,
      );
      if (status != 0) {
        throw StateError('The machine could not open its echo and gain stages');
      }
      return _enhancer = out.value;
    } finally {
      calloc.free(out);
    }
  }

  Pointer<Int16> _scratchFor(int samples) {
    final held = _scratch;
    if (held != null && _scratchSamples >= samples) return held;
    if (held != null) calloc.free(held);
    _scratchSamples = samples;
    return _scratch = calloc<Int16>(samples);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final enhancer = _enhancer;
    if (enhancer != null) _close(enhancer);
    _enhancer = null;
    final scratch = _scratch;
    if (scratch != null) calloc.free(scratch);
    _scratch = null;
  }
}

typedef _OpenEnhancerNative =
    Int32 Function(Int32, Int32, Pointer<Pointer<Void>>);
typedef _OpenEnhancer = int Function(int, int, Pointer<Pointer<Void>>);
typedef _EnhanceFrameNative =
    Int32 Function(Pointer<Void>, Pointer<Int16>, Int32, Int32);
typedef _EnhanceFrame = int Function(Pointer<Void>, Pointer<Int16>, int, int);
typedef _CloseEnhancerNative = Void Function(Pointer<Void>);
typedef _CloseEnhancer = void Function(Pointer<Void>);
