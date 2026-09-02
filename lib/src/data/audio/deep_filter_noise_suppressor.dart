import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../domain/voice_processing.dart';

typedef _DfCreateNative =
    Pointer<Void> Function(Pointer<Utf8>, Float, Pointer<Utf8>);
typedef _DfCreate =
    Pointer<Void> Function(Pointer<Utf8>, double, Pointer<Utf8>);
typedef _DfFrameLengthNative = Size Function(Pointer<Void>);
typedef _DfFrameLength = int Function(Pointer<Void>);
typedef _DfProcessNative =
    Float Function(Pointer<Void>, Pointer<Float>, Pointer<Float>);
typedef _DfProcess =
    double Function(Pointer<Void>, Pointer<Float>, Pointer<Float>);
typedef _DfFreeNative = Void Function(Pointer<Void>);
typedef _DfFree = void Function(Pointer<Void>);

/// DeepFilterNet through libDF's C API (`df.dll`, built by
/// `tool/build_deepfilternet.ps1`).
///
/// The model is mono, 48 kHz, one 10 ms hop at a time. A stereo frame is
/// downmixed for the model and the cleaned signal is written to every
/// channel: a Discord call is heard in mono, and running the network twice
/// would double the CPU for a difference nobody hears.
final class DeepFilterNoiseSuppressor implements VoiceNoiseSuppressor {
  DeepFilterNoiseSuppressor._(DynamicLibrary library, this._state)
    : _process = library.lookupFunction<_DfProcessNative, _DfProcess>(
        'df_process_frame',
      ),
      _free = library.lookupFunction<_DfFreeNative, _DfFree>('df_free'),
      hopSize = library.lookupFunction<_DfFrameLengthNative, _DfFrameLength>(
        'df_get_frame_length',
      )(_state) {
    _input = calloc<Float>(hopSize);
    _output = calloc<Float>(hopSize);
  }

  static const libraryFileName = 'df.dll';
  static const modelFileName = 'DeepFilterNet3_onnx.tar.gz';

  /// Files beside the executable, where the bundle installs them.
  static String bundledPath(String fileName) =>
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}$fileName';

  /// A way to open the bundled suppressor, or null when this build has none:
  /// another platform, or a bundle missing the library or the model.
  ///
  /// Probed once here so a settings surface offers a switch only for a filter
  /// that can actually be switched on.
  static Future<VoiceNoiseSuppressor> Function()? bundledFactory() {
    if (!Platform.isWindows) return null;
    final model = bundledPath(modelFileName);
    if (!File(model).existsSync()) return null;
    try {
      DynamicLibrary.open(libraryFileName);
    } on Object {
      return null;
    }
    return () => open(libraryPath: libraryFileName, modelPath: model);
  }

  /// Opens the library and loads the model, off the calling isolate: the load
  /// takes the better part of a second, which is not a stall the UI or the
  /// microphone path can afford.
  ///
  /// The model archive is checked first because libDF aborts the whole
  /// process on one it cannot read, which is not a failure a caller could
  /// catch; a truncated download would otherwise crash every call.
  static Future<DeepFilterNoiseSuppressor> open({
    required String libraryPath,
    required String modelPath,
    double attenuationLimitDb = 100,
  }) async {
    final state = await Isolate.run(() {
      if (!_isWholeTarball(File(modelPath))) {
        throw StateError('DeepFilterNet model is unreadable: $modelPath');
      }
      final create = DynamicLibrary.open(
        libraryPath,
      ).lookupFunction<_DfCreateNative, _DfCreate>('df_create');
      final path = modelPath.toNativeUtf8();
      try {
        return create(path, attenuationLimitDb, nullptr).address;
      } finally {
        malloc.free(path);
      }
    });
    return DeepFilterNoiseSuppressor._(
      DynamicLibrary.open(libraryPath),
      Pointer<Void>.fromAddress(state),
    );
  }

  /// Whether [file] is a gzip stream holding a complete tar: whole 512-byte
  /// records ending in the two zero records that close an archive. Dart's
  /// gzip decoder hands back what it could read of a truncated stream without
  /// complaint, so the check has to be on the tar inside.
  static bool _isWholeTarball(File file) {
    try {
      final tar = gzip.decode(file.readAsBytesSync());
      if (tar.length < 1024 || tar.length % 512 != 0) return false;
      return tar.skip(tar.length - 1024).every((byte) => byte == 0);
    } on Object {
      return false;
    }
  }

  final Pointer<Void> _state;
  final _DfProcess _process;
  final _DfFree _free;
  late final Pointer<Float> _input;
  late final Pointer<Float> _output;
  bool _disposed = false;

  @override
  final int hopSize;

  @override
  void process(Int16List frame, {required int channels}) {
    if (_disposed) throw StateError('DeepFilterNoiseSuppressor is disposed');
    if (channels <= 0 || frame.length % (hopSize * channels) != 0) {
      throw ArgumentError.value(
        frame.length,
        'frame.length',
        'must hold whole hops of $hopSize samples on each of $channels channels',
      );
    }
    final input = _input.asTypedList(hopSize);
    final output = _output.asTypedList(hopSize);
    final scale = 1 / (32768 * channels);
    for (var hop = 0; hop < frame.length; hop += hopSize * channels) {
      for (var i = 0; i < hopSize; i++) {
        var sum = 0;
        final at = hop + i * channels;
        for (var channel = 0; channel < channels; channel++) {
          sum += frame[at + channel];
        }
        input[i] = sum * scale;
      }
      _process(_state, _input, _output);
      for (var i = 0; i < hopSize; i++) {
        final sample = (output[i] * 32768).round().clamp(-32768, 32767);
        final at = hop + i * channels;
        for (var channel = 0; channel < channels; channel++) {
          frame[at + channel] = sample;
        }
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _free(_state);
    calloc.free(_input);
    calloc.free(_output);
  }
}
