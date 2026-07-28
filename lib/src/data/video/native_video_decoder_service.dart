import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../domain/video_decoder.dart';
import 'native_video_bindings.dart';

/// Decodes a Go Live stream through `flucord_video.dll`.
///
/// The decoder calls back synchronously, from the same thread that submitted
/// the access unit, so an isolate-local callable is enough here — unlike the
/// encoder, which reports from its own capture thread.
final class NativeVideoDecoderService implements VideoDecoderService {
  NativeVideoDecoderService({NativeVideoBindings? bindings})
    : _bindings = bindings ?? _openLibrary();

  static NativeVideoBindings? _openLibrary() {
    if (!Platform.isWindows) return null;
    try {
      return NativeVideoBindings(DynamicLibrary.open('flucord_video.dll'));
    } on Object {
      return null;
    }
  }

  final NativeVideoBindings? _bindings;
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();

  Pointer<Void> _handle = nullptr;
  NativeCallable<NativePictureCallback>? _callback;

  @override
  bool get isSupported => _bindings != null;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {
    final bindings = _bindings;
    if (bindings == null || _handle != nullptr) return;
    final callback = NativeCallable<NativePictureCallback>.isolateLocal(
      _onPicture,
    );
    final out = calloc<Pointer<Void>>();
    try {
      final status = bindings.decoderOpen(
        callback.nativeFunction,
        nullptr,
        out,
      );
      if (status != NativeVideoStatus.ok) {
        callback.close();
        return;
      }
      _handle = out.value;
      _callback = callback;
    } finally {
      calloc.free(out);
    }
  }

  @override
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp}) async {
    final bindings = _bindings;
    if (bindings == null || _handle == nullptr || accessUnit.isEmpty) return;
    final buffer = calloc<Uint8>(accessUnit.length);
    try {
      buffer.asTypedList(accessUnit.length).setAll(0, accessUnit);
      // Pictures arrive on the callback before this returns, which is why the
      // buffer can be freed immediately afterwards.
      bindings.decoderSubmit(
        _handle,
        buffer,
        accessUnit.length,
        timestamp?.inMicroseconds ?? 0,
      );
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  Future<void> stop() async {
    if (_handle == nullptr) return;
    _bindings?.decoderClose(_handle);
    _handle = nullptr;
    _callback?.close();
    _callback = null;
  }

  void _onPicture(
    Pointer<Void> userData,
    Pointer<Uint8> pixels,
    int width,
    int height,
    int stride,
    int timestampUs,
  ) {
    if (width <= 0 || height <= 0 || _frames.isClosed) return;
    final length = width * height * 4;
    // Copied while the decoder still owns the buffer: it reuses the same one
    // for every picture, so a view would show the next frame's contents.
    _frames.add(
      DecodedVideoFrame(
        pixels: Uint8List.fromList(pixels.asTypedList(length)),
        width: width,
        height: height,
        timestamp: Duration(microseconds: timestampUs),
      ),
    );
  }

  Future<void> close() async {
    await stop();
    if (!_frames.isClosed) await _frames.close();
  }
}
