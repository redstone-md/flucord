import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../domain/video_encoder.dart';
import 'native_camera_names.dart';
import 'native_video_bindings.dart';

/// Screen capture and H.264 encoding through `flucord_video.dll`.
///
/// The native lifecycle is owned here and nowhere else: frames are copied
/// before the native buffer is released, the callable is closed only after
/// the native close has joined the capture thread, and a handle nobody
/// stopped is closed by a finalizer rather than leaked with the isolate.
///
/// The native side calls back on its own capture thread, which Dart cannot be
/// entered from directly, so frames cross over a native port: the callback is
/// a `NativeCallable.listener` and the bytes are copied before the native
/// buffer is released.
final class NativeVideoEncoderService
    implements
        VideoEncoderService,
        VideoBitrateControl,
        VideoFrameSinkControl,
        Finalizable {
  NativeVideoEncoderService({NativeVideoBindings? bindings})
    : _bindings = bindings ?? _openLibrary(),
      // After the initializer above, the resident library is open whenever
      // there was one to open, so the finalizer can be built from either it
      // or the bindings this service was handed.
      _finalizer = _finalizerFor(bindings);

  /// The module, opened once for the whole process.
  ///
  /// Kept for the process lifetime on purpose: the finalizer below holds the
  /// address of the module's close, and a module nobody holds a handle to
  /// could be unmapped before the finalizer gets to call it.
  static NativeVideoBindings? _residentLibrary;

  static NativeVideoBindings? _openLibrary() {
    if (!Platform.isWindows) return null;
    if (_residentLibrary != null) return _residentLibrary;
    try {
      return _residentLibrary = NativeVideoBindings(
        DynamicLibrary.open('flucord_video.dll'),
      );
    } on Object {
      // A build without the native module still runs; Go Live simply reports
      // itself unavailable rather than the whole client failing to start.
      return null;
    }
  }

  static NativeFinalizer? _handleFinalizer;

  /// Pairs a leaked handle with its close. Built once, so the close address
  /// outlives every service that shares it.
  static NativeFinalizer? _finalizerFor(NativeVideoBindings? bindings) {
    final library = bindings ?? _residentLibrary;
    if (library == null) return null;
    return _handleFinalizer ??= NativeFinalizer(library.closeAddress);
  }

  final NativeVideoBindings? _bindings;
  final NativeFinalizer? _finalizer;
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();

  Pointer<Void> _handle = nullptr;
  NativeCallable<NativeFrameCallback>? _callback;
  int? _nativeFrameSink;

  @override
  set nativeFrameSink(int? address) => _nativeFrameSink = address;

  @override
  bool get isSupported => _bindings != null;

  @override
  int get displayCount => _bindings?.displayCount() ?? 0;

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  VideoEncoderDiagnostics? get diagnostics {
    final bindings = _bindings;
    final handle = _handle;
    if (bindings == null || handle == nullptr) return null;

    var name = '';
    final nameFunction = bindings.encoderName;
    if (nameFunction != null) {
      const capacity = 256;
      final buffer = calloc<Uint8>(capacity);
      try {
        final length = nameFunction(handle, buffer, capacity);
        if (length > 0) {
          name = buffer.cast<Utf8>().toDartString(length: length);
        }
      } finally {
        calloc.free(buffer);
      }
    }

    final timingsFunction = bindings.stageTimings;
    if (timingsFunction == null) {
      return name.isEmpty
          ? null
          : VideoEncoderDiagnostics(
              encoderName: name,
              captureWaitNs: 0,
              convertNs: 0,
              encodeNs: 0,
              frames: 0,
            );
    }
    final values = calloc<Int64>(4);
    try {
      timingsFunction(handle, values);
      return VideoEncoderDiagnostics(
        encoderName: name,
        captureWaitNs: values[0],
        convertNs: values[1],
        encodeNs: values[2],
        frames: values[3],
      );
    } finally {
      calloc.free(values);
    }
  }

  @override
  Future<void> start(VideoEncoderSettings settings) async {
    final bindings = _bindings;
    if (bindings == null) {
      throw const VideoEncoderException(VideoEncoderFailure.unsupported);
    }
    if (_handle != nullptr || !settings.isValid) {
      throw const VideoEncoderException(VideoEncoderFailure.state);
    }

    // Frames go to another isolate's listener when one was named, and to
    // this service's own otherwise.
    final sink = _nativeFrameSink;
    final callback = sink == null
        ? NativeCallable<NativeFrameCallback>.listener(_onFrame)
        : null;
    final target =
        callback?.nativeFunction ??
        Pointer<NativeFunction<NativeFrameCallback>>.fromAddress(sink!);
    final config = calloc<NativeVideoConfig>();
    final out = calloc<Pointer<Void>>();
    try {
      config.ref
        ..displayIndex = settings.displayIndex
        ..width = settings.width
        ..height = settings.height
        ..framesPerSecond = settings.framesPerSecond
        ..bitrate = settings.bitrate;
      // The two openers take the same config and answer on the same callback;
      // only where the pictures come from differs.
      final open = settings.source == VideoCaptureSource.camera
          ? bindings.openCamera
          : bindings.open;
      final status = open(config, target, nullptr, out);
      if (status != NativeVideoStatus.ok) {
        callback?.close();
        throw VideoEncoderException(
          _failureFor(status),
          platformCode: _bindings?.lastError?.call(),
          platformStage: _bindings?.lastErrorStage?.call(),
        );
      }
      _handle = out.value;
      _callback = callback;
      // The finalizer closes what stop might never get to: a service dropped
      // while capturing would otherwise take the handle and the isolate's
      // liveness with it.
      _finalizer?.attach(this, out.value, detach: this);
    } finally {
      calloc
        ..free(config)
        ..free(out);
    }
  }

  @override
  Future<bool> setBitrate(int bitsPerSecond) async {
    final setBitrate = _bindings?.setBitrate;
    if (_handle == nullptr || setBitrate == null) return false;
    return setBitrate(_handle, bitsPerSecond) == NativeVideoStatus.ok;
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
    _finalizer?.detach(this);
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

  @override
  List<String> get cameraNames {
    final bindings = _bindings;
    if (bindings == null) return const [];
    return NativeCameraNames.read(
      count: bindings.cameraCount(),
      name: bindings.cameraName,
    );
  }

  static VideoEncoderFailure _failureFor(int status) => switch (status) {
    NativeVideoStatus.noDisplay => VideoEncoderFailure.noDisplay,
    NativeVideoStatus.noCamera => VideoEncoderFailure.noCamera,
    NativeVideoStatus.encoder => VideoEncoderFailure.encoder,
    NativeVideoStatus.state => VideoEncoderFailure.state,
    _ => VideoEncoderFailure.unsupported,
  };

  Future<void> close() async {
    await stop();
    if (!_frames.isClosed) await _frames.close();
  }
}
