import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../app_log.dart';
import '../../domain/video_decoder.dart';
import 'native_video_bindings.dart';

/// Decodes a Go Live stream through `flucord_video.dll`.
///
/// The service is a proxy: a worker isolate owns every native handle, so the
/// per-picture copy, the close and the join of the decode thread all run off
/// the main isolate, and an open that fails is an error the caller hears
/// rather than a silence. See docs/NATIVE_MEDIA.md for the whole story.
final class NativeVideoDecoderService implements VideoDecoderService {
  NativeVideoDecoderService({String? libraryPath})
    : _libraryPath = libraryPath ?? _defaultLibrary;

  static const _defaultLibrary = 'flucord_video.dll';

  /// Where the worker finds the native module. The app runs on the default
  /// search; the probe tool hands over a path.
  final String _libraryPath;

  final int _id = _DecoderWorker.instance.nextId();

  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  final StreamController<int> _dropped = StreamController.broadcast();

  bool? _supported;
  bool _open = false;

  @override
  bool get isSupported => _supported ??= _openModule(_libraryPath) != null;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  /// The worker polls the dropped count with every picture and reports the
  /// growth the moment it sees it, not on a timer.
  @override
  Stream<int> get droppedAccessUnits => _dropped.stream;

  @override
  Future<void> start() async {
    if (_open) return;
    _open = true;
    _DecoderWorker.instance.register(
      _id,
      onPicture: (frame) {
        if (!_frames.isClosed) _frames.add(frame);
      },
      onDrop: (dropped) {
        if (dropped <= 3 || dropped % 20 == 0) {
          AppLog.warning('video', 'decode dropped $dropped access units');
        }
        if (!_dropped.isClosed) _dropped.add(dropped);
      },
    );
    try {
      await _DecoderWorker.instance.open(_id, _libraryPath);
    } on Object {
      _open = false;
      _DecoderWorker.instance.unregister(_id);
      rethrow;
    }
  }

  @override
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp}) async {
    if (!_open || accessUnit.isEmpty) return;
    final port = await _DecoderWorker.instance.port();
    port.send(
      _Submit(_id, TransferableTypedData.fromList([accessUnit]), timestamp),
    );
  }

  @override
  Future<void> stop() async {
    if (!_open) return;
    _open = false;
    await _DecoderWorker.instance.closeDecoder(_id);
    _DecoderWorker.instance.unregister(_id);
  }

  Future<void> close() async {
    await stop();
    if (!_frames.isClosed) await _frames.close();
    if (!_dropped.isClosed) await _dropped.close();
  }
}

/// Opens the native module, or answers null and says why to the log. Shared
/// by the main isolate's support probe and the worker's own open.
NativeVideoBindings? _openModule(String path) {
  if (!Platform.isWindows) return null;
  try {
    return NativeVideoBindings(DynamicLibrary.open(path));
  } on Object catch (error) {
    // A silent null here reads as "this build cannot decode", and every
    // stream control dies for a reason nobody can see.
    AppLog.warning('video', '$path failed to load: $error');
    return null;
  }
}

/// The process's one decoder worker, spawned on first use and kept for the
/// life of the app. Every message it sends names the service that owns it,
/// and the main-isolate routing below hands each one over.
final class _DecoderWorker {
  _DecoderWorker._();

  static final _DecoderWorker instance = _DecoderWorker._();

  /// How long an open or a close waits for the worker's answer: a worker
  /// that answers in milliseconds is normal, and one that never answers
  /// must surface as an error rather than a spinner.
  static const _replyTimeout = Duration(seconds: 3);

  final ReceivePort _inbox = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final Completer<SendPort> _ready = Completer();
  Future<void>? _spawning;

  int _nextId = 0;
  final Map<int, Completer<void>> _opens = {};
  final Map<int, Completer<void>> _closes = {};
  final Map<int, _Route> _routes = {};

  int nextId() => _nextId++;

  Future<SendPort> port() {
    _spawning ??= _spawn();
    return _ready.future;
  }

  Future<void> _spawn() async {
    _inbox.listen(_onMessage);
    _errors.listen(
      (message) =>
          AppLog.error('video', 'decoder worker error', error: message),
    );
    try {
      await Isolate.spawn(
        _decoderWorkerMain,
        _inbox.sendPort,
        onError: _errors.sendPort,
        // A stray exception in one decoder must not take the others with
        // it; it is logged through the error port instead.
        errorsAreFatal: false,
        debugName: 'flucord-video-decoder',
      );
    } on Object catch (error, stackTrace) {
      if (!_ready.isCompleted) _ready.completeError(error, stackTrace);
    }
  }

  /// Opens decoder [id], failing when the module cannot load, the decoder
  /// refuses, or the worker never answers.
  Future<void> open(int id, String libraryPath) async {
    final completer = Completer<void>();
    _opens[id] = completer;
    final SendPort port;
    try {
      port = await this.port();
      port.send(_Open(id, libraryPath));
    } on Object {
      _opens.remove(id);
      rethrow;
    }
    try {
      await completer.future.timeout(
        _replyTimeout,
        onTimeout: () {
          throw StateError('the decoder did not answer its open');
        },
      );
    } on Object {
      _opens.remove(id);
      // The worker may still answer, after the caller has given up: a close
      // queued now disposes whatever eventually opened, and a later open on
      // this service queues behind it.
      port.send(_Close(id));
      rethrow;
    }
  }

  Future<void> closeDecoder(int id) async {
    final completer = Completer<void>();
    _closes[id] = completer;
    try {
      final port = await this.port();
      port.send(_Close(id));
      await completer.future.timeout(
        _replyTimeout,
        onTimeout: () {
          // The decoder and its callback are the worker's to close; a close
          // it never finished is a leak, and one worth seeing.
          AppLog.warning('video', 'decoder $id did not answer its close');
        },
      );
    } finally {
      _closes.remove(id);
    }
  }

  void register(
    int id, {
    required void Function(DecodedVideoFrame frame) onPicture,
    required void Function(int dropped) onDrop,
  }) {
    _routes[id] = (onPicture: onPicture, onDrop: onDrop);
  }

  void unregister(int id) {
    _routes.remove(id);
  }

  void _onMessage(Object? message) {
    switch (message) {
      case _Hello(:final port):
        if (!_ready.isCompleted) _ready.complete(port);
      case _Log(:final level, :final scope, :final message, :final error):
        AppLog.record(level, scope, message, error: error);
      case _Opened(:final id):
        _opens.remove(id)?.complete();
      case _OpenFailed(:final id, :final reason):
        _opens.remove(id)?.completeError(StateError(reason));
      case _Closed(:final id):
        _closes.remove(id)?.complete();
      case _Picture(
        :final id,
        :final bytes,
        :final width,
        :final height,
        :final timestamp,
      ):
        _routes[id]?.onPicture(
          DecodedVideoFrame(
            pixels: bytes.materialize().asUint8List(),
            width: width,
            height: height,
            timestamp: timestamp,
          ),
        );
      case _Dropped(:final id, :final total):
        _routes[id]?.onDrop(total);
    }
  }
}

/// The worker isolate: every native decoder call happens here, from the open
/// to the close and the join it waits on.
Future<void> _decoderWorkerMain(SendPort toMain) async {
  final inbox = ReceivePort();
  // The log file belongs to the main isolate; a worker hands its records
  // over instead of opening a second handle on the same file.
  AppLog.redirect = (level, scope, message, error) =>
      toMain.send(_Log(level, scope, message, error?.toString()));
  toMain.send(_Hello(inbox.sendPort));

  final decoders = <int, _NativeDecoder>{};
  final modules = <String, NativeVideoBindings?>{};
  await for (final message in inbox) {
    try {
      switch (message) {
        case _Open(:final id, :final libraryPath):
          final bindings = modules.putIfAbsent(
            libraryPath,
            () => _openModule(libraryPath),
          );
          if (bindings == null) {
            toMain.send(
              _OpenFailed(id, 'the native video module failed to load'),
            );
            break;
          }
          final (decoder, status) = _NativeDecoder.open(bindings, id, toMain);
          if (decoder == null) {
            toMain.send(
              _OpenFailed(id, 'the decoder refused to open ($status)'),
            );
          } else {
            decoders[id] = decoder;
            toMain.send(_Opened(id));
          }
        case _Submit(:final id, :final unit, :final timestamp):
          decoders[id]?.submit(unit.materialize().asUint8List(), timestamp);
        case _Close(:final id):
          decoders.remove(id)?.close();
          toMain.send(_Closed(id));
      }
    } on Object catch (error, stackTrace) {
      // One bad message must not take the worker down: every decoder opened
      // after it would be answered by a worker that says nothing.
      AppLog.error(
        'video',
        'decoder worker failed to handle a message',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// One native decoder on the worker: its handle, its picture callback, and
/// the accounting it is polled for.
final class _NativeDecoder {
  _NativeDecoder._(this._bindings, this._id, this._toMain);

  /// Opens the decoder, or answers null with the status the module returned
  /// when it refused.
  static (_NativeDecoder?, int) open(
    NativeVideoBindings bindings,
    int id,
    SendPort toMain,
  ) {
    final decoder = _NativeDecoder._(bindings, id, toMain);
    decoder._callback = NativeCallable<NativePictureCallback>.listener(
      decoder._onPicture,
    );
    final out = calloc<Pointer<Void>>();
    try {
      final status = bindings.decoderOpen(
        decoder._callback!.nativeFunction,
        nullptr,
        out,
      );
      if (status != NativeVideoStatus.ok) {
        decoder._callback?.close();
        decoder._callback = null;
        return (null, status);
      }
      decoder._handle = out.value;
      decoder._stats = Timer.periodic(
        const Duration(seconds: 3),
        (_) => decoder._reportStats(),
      );
      return (decoder, status);
    } finally {
      calloc.free(out);
    }
  }

  final NativeVideoBindings _bindings;
  final int _id;
  final SendPort _toMain;

  Pointer<Void> _handle = nullptr;
  NativeCallable<NativePictureCallback>? _callback;
  Timer? _stats;
  int _submitFailures = 0;
  bool _loggedInfo = false;
  int _reportedSubmitted = -1;
  int _reportedDropped = 0;

  void submit(Uint8List accessUnit, Duration? timestamp) {
    if (_handle == nullptr || accessUnit.isEmpty) return;
    final buffer = calloc<Uint8>(accessUnit.length);
    try {
      buffer.asTypedList(accessUnit.length).setAll(0, accessUnit);
      // Pictures arrive on the callback before this returns, which is why
      // the buffer can be freed immediately afterwards.
      final status = _bindings.decoderSubmit(
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

  void close() {
    _stats?.cancel();
    _stats = null;
    _bindings.decoderClose(_handle);
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
    if (width <= 0 || height <= 0 || pixels == nullptr) return;
    if (!_loggedInfo) {
      _loggedInfo = true;
      // By the first picture the decoder has settled its output type, which
      // is the moment an unexpected format or row pitch can be seen.
      _logDecoderInfo();
    }
    // One copy, made here rather than on the main isolate: the transferable
    // buffer is built straight out of native memory, and the main isolate
    // adopts it without a second one. The buffer is ours until released, so
    // the copy has no race with the next picture.
    final bytes = TransferableTypedData.fromList([
      pixels.asTypedList(width * height * 4),
    ]);
    _bindings.decoderReleasePicture?.call(pixels.cast<Void>());
    _toMain.send(
      _Picture(_id, bytes, width, height, Duration(microseconds: timestampUs)),
    );
    // A drop the decode queue made is seen by the next picture, so the
    // keyframe it needs is asked for at once instead of when the stats
    // timer next runs.
    final dropped = _bindings.decoderDropped?.call(_handle) ?? 0;
    if (dropped > _reportedDropped) {
      _reportedDropped = dropped;
      _toMain.send(_Dropped(_id, dropped));
    }
  }

  /// Periodically says where the frames' time went, for a decoder that has
  /// gone quiet: did the pictures die on the way in, or never come out of
  /// the transform? Drops themselves are reported with the picture that
  /// follows them; the timer covers a decoder that has stopped producing
  /// pictures to follow.
  void _reportStats() {
    final stats = _bindings.decoderStats;
    if (stats == null || _handle == nullptr) return;
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
        _handle,
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
      String hex(int value) =>
          value == 0 ? '-' : '0x${value.toRadixString(16)}';
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
        _toMain.send(_Dropped(_id, totalDropped));
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
  void _logDecoderInfo() {
    final info = _bindings.decoderInfo;
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
}

// The messages between the proxy and the worker.

final class _Hello {
  const _Hello(this.port);

  final SendPort port;
}

/// Where a decoder service's pictures and drops go once they arrive.
typedef _Route = ({
  void Function(DecodedVideoFrame frame) onPicture,
  void Function(int dropped) onDrop,
});

final class _Log {
  const _Log(this.level, this.scope, this.message, this.error);

  final AppLogLevel level;
  final String scope;
  final String message;
  final String? error;
}

final class _Open {
  const _Open(this.id, this.libraryPath);

  final int id;
  final String libraryPath;
}

final class _Opened {
  const _Opened(this.id);

  final int id;
}

final class _OpenFailed {
  const _OpenFailed(this.id, this.reason);

  final int id;
  final String reason;
}

final class _Submit {
  const _Submit(this.id, this.unit, this.timestamp);

  final int id;
  final TransferableTypedData unit;
  final Duration? timestamp;
}

final class _Picture {
  const _Picture(this.id, this.bytes, this.width, this.height, this.timestamp);

  final int id;
  final TransferableTypedData bytes;
  final int width;
  final int height;
  final Duration timestamp;
}

final class _Dropped {
  const _Dropped(this.id, this.total);

  final int id;
  final int total;
}

final class _Close {
  const _Close(this.id);

  final int id;
}

final class _Closed {
  const _Closed(this.id);

  final int id;
}
