import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../app_log.dart';
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
    } on Object catch (error) {
      // A silent null here reads as "this build cannot decode", and every
      // stream control dies for a reason nobody can see.
      AppLog.warning('video', 'flucord_video.dll failed to load: $error');
      return null;
    }
  }

  final NativeVideoBindings? _bindings;
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();

  Pointer<Void> _handle = nullptr;
  NativeCallable<NativePictureCallback>? _callback;
  int _submitFailures = 0;
  bool _loggedInfo = false;
  int _loggedDropped = 0;
  Timer? _statsTimer;
  int _reportedSubmitted = -1;
  int _reportedDropped = 0;

  /// Told when the decoder's own queue had to drop an access unit: a dropped
  /// one breaks the reference chain, so the caller asks for a keyframe and
  /// stops drawing until it lands.
  void Function(int dropped)? onDecoderDrop;

  @override
  bool get isSupported => _bindings != null;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {
    final bindings = _bindings;
    if (bindings == null || _handle != nullptr) return;
    // The decode runs on the DLL's own thread, so the callback is delivered
    // asynchronously: a synchronous one would tie the decode back to the
    // thread that submits, which is the thread that draws the interface.
    final callback = NativeCallable<NativePictureCallback>.listener(
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
      _statsTimer?.cancel();
      _statsTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _reportDecoderStats(),
      );
    } finally {
      calloc.free(out);
    }
  }

  /// Periodically answers the only question that matters when pictures
  /// vanish: did they die on the way in, or never come out of the transform?
  /// The DLL counts every step, because a silent `FAILED(hr)` return used to
  /// swallow exactly this.
  void _reportDecoderStats() {
    final bindings = _bindings;
    final handle = _handle;
    final stats = bindings?.decoderStats;
    if (stats == null || handle == nullptr) return;
    final submitted = calloc<Int64>();
    final notAccepting = calloc<Int64>();
    final inputErrors = calloc<Int64>();
    final lastInputError = calloc<Int64>();
    final outputs = calloc<Int64>();
    final outputErrors = calloc<Int64>();
    final lastOutputError = calloc<Int64>();
    final dropped = calloc<Int32>();
    try {
      stats(
        handle,
        submitted,
        notAccepting,
        inputErrors,
        lastInputError,
        outputs,
        outputErrors,
        lastOutputError,
        dropped,
      );
      final totalSubmitted = submitted.value;
      final totalDropped = dropped.value;
      if (totalSubmitted == _reportedSubmitted) return;
      _reportedSubmitted = totalSubmitted;
      String hex(int value) => value == 0 ? '-' : '0x${value.toRadixString(16)}';
      AppLog.warning(
        'video',
        'decoder stats: submitted $totalSubmitted, outputs ${outputs.value}, '
        'not-accepting ${notAccepting.value}, input errors '
        '${inputErrors.value} (${hex(lastInputError.value)}), output errors '
        '${outputErrors.value} (${hex(lastOutputError.value)}), '
        'queue dropped $totalDropped',
      );
      if (totalDropped > _reportedDropped) {
        _reportedDropped = totalDropped;
        onDecoderDrop?.call(totalDropped);
      }
    } finally {
      calloc.free(submitted);
      calloc.free(notAccepting);
      calloc.free(inputErrors);
      calloc.free(lastInputError);
      calloc.free(outputs);
      calloc.free(outputErrors);
      calloc.free(lastOutputError);
      calloc.free(dropped);
    }
  }

  /// Says what the decoder actually settled on. An output type nobody
  /// assumed — a different pixel format, a padded row pitch — draws a picture
  /// that looks corrupted in ways the wire can never explain.
  void _logDecoderInfo(NativeVideoBindings bindings) {
    final info = bindings.decoderInfo;
    if (info == null || _handle == nullptr) return;
    final fourcc = calloc<Int32>();
    final width = calloc<Int32>();
    final height = calloc<Int32>();
    final stride = calloc<Int32>();
    try {
      final status = info(_handle, fourcc, width, height, stride);
      if (status != NativeVideoStatus.ok) return;
      final tag = fourcc.value;
      final name = String.fromCharCodes([
        tag & 0xff,
        (tag >> 8) & 0xff,
        (tag >> 16) & 0xff,
        (tag >> 24) & 0xff,
      ]);
      AppLog.warning(
        'video',
        'decoder output: $name ${width.value}x${height.value} '
        'stride ${stride.value}',
      );
    } finally {
      calloc.free(fourcc);
      calloc.free(width);
      calloc.free(height);
      calloc.free(stride);
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
      final status = bindings.decoderSubmit(
        _handle,
        buffer,
        accessUnit.length,
        timestamp?.inMicroseconds ?? 0,
      );
      // A rejected access unit is a gap in the decoder's reference chain:
      // every later picture smears until a keyframe. Rare and worth seeing.
      if (status != NativeVideoStatus.ok && _submitFailures++ < 5) {
        AppLog.warning('video', 'decoder rejected an access unit: $status');
      }
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  Future<void> stop() async {
    _statsTimer?.cancel();
    _statsTimer = null;
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
    final bindings = _bindings;
    if (width <= 0 || height <= 0 || bindings == null || _frames.isClosed) {
      return;
    }
    if (!_loggedInfo) {
      _loggedInfo = true;
      // By the first picture the decoder has settled its output type, which
      // is the moment an unexpected format or row pitch can be seen.
      _logDecoderInfo(bindings);
    }
    final length = width * height * 4;
    // The buffer is ours until released, so the copy has no race with the
    // next picture: the decode thread allocates a fresh one each time.
    final frame = Uint8List.fromList(pixels.asTypedList(length));
    bindings.decoderReleasePicture?.call(pixels.cast<Void>());
    final dropped = bindings.decoderDropped?.call(_handle) ?? 0;
    if (dropped > _loggedDropped && (dropped <= 3 || dropped % 20 == 0)) {
      _loggedDropped = dropped;
      AppLog.warning('video', 'decode dropped $dropped access units');
    }
    _frames.add(
      DecodedVideoFrame(
        pixels: frame,
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
