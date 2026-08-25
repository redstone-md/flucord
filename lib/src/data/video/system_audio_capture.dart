import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// One block of what the machine is playing.
final class SystemAudioChunk {
  const SystemAudioChunk({
    required this.samples,
    required this.channels,
    required this.sampleRate,
  });

  /// Interleaved 16-bit PCM.
  final Int16List samples;

  final int channels;
  final int sampleRate;

  /// How many sample frames, which is not the sample count on anything but a
  /// mono endpoint.
  int get frameCount => channels == 0 ? 0 : samples.length ~/ channels;
}

/// The sound of what is being shared.
///
/// A share's audio is not the microphone. Discord sends the shared
/// application's sound on the stream connection, so a viewer hears the game
/// rather than the room; a client that reused the voice uplink for it would
/// put the game into the voice channel, where everybody hears it whether they
/// opened the stream or not.
abstract interface class SystemAudioCapture {
  bool get isSupported;
  bool get isRunning;

  /// Blocks as they arrive, until [stop].
  Stream<SystemAudioChunk> get chunks;

  /// Answers whether the endpoint opened — a machine with no output device
  /// has nothing to capture, and saying otherwise would promise silence as
  /// sound.
  Future<bool> start();

  Future<void> stop();
}

/// A capture on a build with no module for it.
final class UnavailableSystemAudioCapture implements SystemAudioCapture {
  const UnavailableSystemAudioCapture();

  @override
  bool get isSupported => false;

  @override
  bool get isRunning => false;

  @override
  Stream<SystemAudioChunk> get chunks => const Stream<SystemAudioChunk>.empty();

  @override
  Future<bool> start() async => false;

  @override
  Future<void> stop() async {}
}

typedef _AudioCallback =
    Void Function(Pointer<Void>, Pointer<Int16>, Int32, Int32, Int32);

/// WASAPI loopback through `flucord_audio.dll`.
final class WindowsSystemAudioCapture implements SystemAudioCapture {
  WindowsSystemAudioCapture()
    : this.withLibrary(Platform.isWindows ? _open() : null);

  /// The module handed in rather than opened, so a test can state that it is
  /// genuinely absent.
  WindowsSystemAudioCapture.withLibrary(this._library);

  static DynamicLibrary? _open() {
    try {
      return DynamicLibrary.open('flucord_audio.dll');
    } on Object {
      return null;
    }
  }

  final DynamicLibrary? _library;
  final StreamController<SystemAudioChunk> _chunks =
      StreamController.broadcast();
  NativeCallable<_AudioCallback>? _callback;
  Pointer<Void> _handle = nullptr;

  @override
  bool get isSupported => _library != null;

  @override
  bool get isRunning => _handle != nullptr;

  @override
  Stream<SystemAudioChunk> get chunks => _chunks.stream;

  @override
  Future<bool> start() async {
    final library = _library;
    if (library == null || _handle != nullptr) return _handle != nullptr;
    final callback = NativeCallable<_AudioCallback>.listener(_onFrames);
    final out = calloc<Pointer<Void>>();
    try {
      final status = library
          .lookupFunction<
            Int32 Function(
              Pointer<NativeFunction<_AudioCallback>>,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<NativeFunction<_AudioCallback>>,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            )
          >(
            'flucord_audio_open_loopback',
          )(callback.nativeFunction, nullptr, out);
      if (status != 0) {
        callback.close();
        return false;
      }
      _handle = out.value;
      _callback = callback;
      return true;
    } finally {
      calloc.free(out);
    }
  }

  @override
  Future<void> stop() async {
    final library = _library;
    if (library == null || _handle == nullptr) return;
    library.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('flucord_audio_close')(_handle);
    _handle = nullptr;
    // Closed after the native close returns: that call joins the capture
    // thread, so no further callback can be in flight.
    _callback?.close();
    _callback = null;
  }

  void _onFrames(
    Pointer<Void> userData,
    Pointer<Int16> frames,
    int frameCount,
    int channels,
    int sampleRate,
  ) {
    if (frameCount <= 0 || channels <= 0 || _chunks.isClosed) return;
    _chunks.add(
      SystemAudioChunk(
        // Copied: the buffer belongs to the endpoint and is released the
        // moment the callback returns.
        samples: Int16List.fromList(frames.asTypedList(frameCount * channels)),
        channels: channels,
        sampleRate: sampleRate,
      ),
    );
  }

  Future<void> close() async {
    await stop();
    if (!_chunks.isClosed) await _chunks.close();
  }
}

/// Interleaved PCM as two channels.
///
/// A share's sound is sent stereo, as Discord sends it: a mono endpoint is
/// doubled, and anything wider keeps its first two channels, which are the
/// front pair on every layout Windows names.
Int16List toStereo(Int16List samples, int channels) {
  if (channels == 2) return samples;
  final frames = samples.length ~/ channels;
  final stereo = Int16List(frames * 2);
  for (var frame = 0; frame < frames; frame++) {
    stereo[frame * 2] = samples[frame * channels];
    stereo[frame * 2 + 1] = samples[frame * channels + (channels > 1 ? 1 : 0)];
  }
  return stereo;
}
