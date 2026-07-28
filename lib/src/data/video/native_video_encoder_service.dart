import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../domain/video_encoder.dart';
import 'native_video_bindings.dart';

/// Screen capture and H.264 encoding through `flucord_video.dll`.
///
/// The native side calls back on its own capture thread, which Dart cannot be
/// entered from directly, so frames cross over a native port: the callback is
/// a `NativeCallable.listener` and the bytes are copied before the native
/// buffer is released.
final class NativeVideoEncoderService implements VideoEncoderService {
  NativeVideoEncoderService({NativeVideoBindings? bindings})
    : _bindings = bindings ?? _openLibrary();

  static NativeVideoBindings? _openLibrary() {
    if (!Platform.isWindows) return null;
    try {
      return NativeVideoBindings(DynamicLibrary.open('flucord_video.dll'));
    } on Object {
      // A build without the native module still runs; Go Live simply reports
      // itself unavailable rather than the whole client failing to start.
      return null;
    }
  }

  final NativeVideoBindings? _bindings;
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();

  Pointer<Void> _handle = nullptr;
  NativeCallable<NativeFrameCallback>? _callback;

  @override
  bool get isSupported => _bindings != null;

  @override
  int get displayCount => _bindings?.displayCount() ?? 0;

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start(VideoEncoderSettings settings) async {
    final bindings = _bindings;
    if (bindings == null) {
      throw const VideoEncoderException(VideoEncoderFailure.unsupported);
    }
    if (_handle != nullptr || !settings.isValid) {
      throw const VideoEncoderException(VideoEncoderFailure.state);
    }

    final callback = NativeCallable<NativeFrameCallback>.listener(_onFrame);
    final config = calloc<NativeVideoConfig>();
    final out = calloc<Pointer<Void>>();
    try {
      config.ref
        ..displayIndex = settings.displayIndex
        ..width = settings.width
        ..height = settings.height
        ..framesPerSecond = settings.framesPerSecond
        ..bitrate = settings.bitrate;
      final status = bindings.open(
        config,
        callback.nativeFunction,
        nullptr,
        out,
      );
      if (status != NativeVideoStatus.ok) {
        callback.close();
        throw VideoEncoderException(_failureFor(status));
      }
      _handle = out.value;
      _callback = callback;
    } finally {
      calloc
        ..free(config)
        ..free(out);
    }
  }

  @override
  Future<void> requestKeyframe() async {
    if (_handle == nullptr) return;
    _bindings?.requestKeyframe(_handle);
  }

  @override
  Future<void> setPaused({required bool paused}) async {
    if (_handle == nullptr) return;
    _bindings?.setPaused(_handle, paused ? 1 : 0);
  }

  @override
  Future<void> stop() async {
    if (_handle == nullptr) return;
    // The native close joins the capture thread, so no further callback can
    // arrive once it returns and the callable is safe to release.
    _bindings?.close(_handle);
    _handle = nullptr;
    _callback?.close();
    _callback = null;
  }

  void _onFrame(
    Pointer<Void> userData,
    Pointer<Uint8> data,
    int length,
    int timestampUs,
    int isKeyframe,
  ) {
    // The buffer is owned from here: the encoder allocated it precisely
    // because this listener runs after the capture thread has moved on.
    try {
      if (length > 0 && !_frames.isClosed) {
        _frames.add(
          EncodedVideoFrame(
            bytes: Uint8List.fromList(data.asTypedList(length)),
            timestamp: Duration(microseconds: timestampUs),
            isKeyframe: isKeyframe != 0,
          ),
        );
      }
    } finally {
      _bindings?.releaseFrame(data);
    }
  }

  static VideoEncoderFailure _failureFor(int status) => switch (status) {
    NativeVideoStatus.noDisplay => VideoEncoderFailure.noDisplay,
    NativeVideoStatus.encoder => VideoEncoderFailure.encoder,
    NativeVideoStatus.state => VideoEncoderFailure.state,
    _ => VideoEncoderFailure.unsupported,
  };

  Future<void> close() async {
    await stop();
    if (!_frames.isClosed) await _frames.close();
  }
}
