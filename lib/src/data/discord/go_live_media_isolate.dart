import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import '../../app_log.dart';
import '../../domain/go_live_media.dart';
import '../../domain/go_live_stream.dart';
import '../../domain/video_encoder.dart';
import '../../domain/voice_connection.dart';
import '../dave/native_dave_service.dart';
import '../video/native_video_bindings.dart';
import 'discord_voice_socket_factory.dart';
import 'go_live_media_plane.dart';
import 'go_live_media_worker.dart';
import 'go_live_sender.dart';

/// The stream, sent from an isolate of its own.
///
/// What Discord does with a media thread: the Sender's whole connection (the
/// signalling socket, the group encryption, the packetiser, the pacer, the
/// transport cipher and the UDP socket) lives on a worker isolate, and the
/// encoder hands its pictures to that isolate directly. The main isolate,
/// which also draws the UI, never holds a picture back: a long build, a
/// garbage collection or a burst of gateway events used to stall the send
/// path for hundreds of milliseconds at a time, and every stall reached the
/// watcher as a freeze followed by a burst.
///
/// The main isolate keeps a proxy per Sender, which speaks the Sender
/// interface and nothing else.
final class GoLiveMediaIsolate implements GoLiveMediaPlane {
  GoLiveMediaIsolate({int Function() maxDaveProtocolVersion = _noDave})
    : _maxDaveProtocolVersion = maxDaveProtocolVersion;

  static const _scope = 'golive.media';

  static int _noDave() => 0;

  /// What DAVE version a Sender's socket offers, read when it is opened:
  /// the worker builds its own group encryptor, so it is told the version
  /// rather than handed the main isolate's factory.
  final int Function() _maxDaveProtocolVersion;

  final ReceivePort _inbox = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final Completer<MediaHello> _hello = Completer();
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();
  final Map<int, _IsolateSender> _senders = {};

  Future<void>? _spawning;
  int _nextId = 0;

  @override
  Future<int?> get nativeFrameSink =>
      _worker().then((hello) => hello.frameSink);

  @override
  Stream<EncodedVideoFrame> get relayedFrames => _frames.stream;

  @override
  GoLiveSender openSender({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
    required VideoEncoderSettings settings,
  }) {
    final id = _nextId++;
    final sender = _IsolateSender(id: id, plane: this);
    _senders[id] = sender;
    _post(
      MediaOpen(
        id: id,
        credentials: credentials,
        streamKey: streamKey,
        settings: settings,
        maxDaveProtocolVersion: _maxDaveProtocolVersion(),
      ),
    );
    return sender;
  }

  Future<void> dispose() async {
    _post(const MediaShutdown());
    for (final sender in _senders.values.toList(growable: false)) {
      sender.finishClose();
    }
    _senders.clear();
    _inbox.close();
    _errors.close();
    await _frames.close();
  }

  /// The worker, spawned on first use and kept for the process.
  Future<MediaHello> _worker() {
    _spawning ??= _spawn();
    return _hello.future;
  }

  Future<void> _spawn() async {
    _inbox.listen(_onMessage);
    _errors.listen(
      (message) => AppLog.error(_scope, 'worker error', error: message),
    );
    try {
      await Isolate.spawn(
        _workerMain,
        _inbox.sendPort,
        onError: _errors.sendPort,
        // A stray exception in one connection must not take the whole plane
        // with it; it is logged through the error port instead.
        errorsAreFatal: false,
        debugName: 'golive-media',
      );
    } on Object catch (error, stackTrace) {
      if (!_hello.isCompleted) _hello.completeError(error, stackTrace);
    }
  }

  void _post(Object message) {
    unawaited(
      _worker().then(
        (hello) => hello.port.send(message),
        onError: (Object error) =>
            AppLog.error(_scope, 'worker unavailable', error: error),
      ),
    );
  }

  void _onMessage(Object? message) {
    switch (message) {
      case MediaHello():
        if (!_hello.isCompleted) _hello.complete(message);
      case MediaStatus(:final id, :final status):
        _senders[id]?.accept(status);
      case MediaCommand(:final id, :final command):
        _senders[id]?._commands.add(command);
      case MediaPaceLine(:final id, :final line):
        _senders[id]?._paceLines.add(line);
      case MediaFrame(:final bytes, :final timestampUs, :final isKeyframe):
        _frames.add(
          EncodedVideoFrame(
            bytes: bytes.materialize().asUint8List(),
            timestamp: Duration(microseconds: timestampUs),
            isKeyframe: isKeyframe,
          ),
        );
      case MediaLog(:final level, :final scope, :final message, :final error):
        AppLog.record(level, scope, message, error: error);
      case MediaClosed(:final id):
        _senders.remove(id)?.finishClose();
    }
  }
}

/// The main isolate's end of one Sender on the worker.
final class _IsolateSender implements GoLiveSender {
  _IsolateSender({required this.id, required GoLiveMediaIsolate plane})
    : _plane = plane;

  /// How long a close waits for the worker to confirm before giving up on
  /// it: a worker that died must not hang the stream plane's teardown.
  static const _closeTimeout = Duration(seconds: 3);

  final int id;
  final GoLiveMediaIsolate _plane;
  final StreamController<GoLiveSenderStatus> _statuses =
      StreamController.broadcast();
  final StreamController<GoLiveEncoderCommand> _commands =
      StreamController.broadcast();
  final StreamController<String> _paceLines = StreamController.broadcast();
  GoLiveSenderStatus _status = GoLiveSenderStatus.dialling;
  Completer<void>? _closing;

  @override
  GoLiveSenderStatus get status => _status;

  @override
  Stream<GoLiveSenderStatus> get statuses => _statuses.stream;

  @override
  Stream<GoLiveEncoderCommand> get encoderCommands => _commands.stream;

  @override
  Stream<String> get paceLines => _paceLines.stream;

  @override
  void reshape(VideoEncoderSettings settings) =>
      _plane._post(MediaReshape(id: id, settings: settings));

  @override
  void sendOpusFrame(Uint8List opus) =>
      _plane._post(MediaAudio(id: id, opus: opus));

  @override
  Future<void> close() async {
    final closing = _closing;
    if (closing != null) return closing.future;
    final completer = _closing = Completer<void>();
    _plane._post(MediaClose(id));
    await completer.future.timeout(_closeTimeout, onTimeout: () {});
    accept(GoLiveSenderStatus.closed);
    await _statuses.close();
    await _commands.close();
    await _paceLines.close();
  }

  void accept(GoLiveSenderStatus status) {
    if (_statuses.isClosed || _status == status) return;
    _status = status;
    _statuses.add(status);
  }

  void finishClose() {
    final closing = _closing;
    if (closing != null && !closing.isCompleted) closing.complete();
  }
}

// The worker isolate.

Future<void> _workerMain(SendPort toMain) async {
  final inbox = ReceivePort();
  AppLog.redirect = (level, scope, message, error) => toMain.send(
    MediaLog(
      level: level,
      scope: scope,
      message: message,
      error: error?.toString(),
    ),
  );
  final frames = _NativeFrameSource.open(toMain);
  toMain.send(MediaHello(port: inbox.sendPort, frameSink: frames?.address));
  NativeDaveService? dave;
  final worker = GoLiveMediaWorker(
    toMain: toMain,
    frames: frames?.frames ?? const Stream<EncodedVideoFrame>.empty(),
    socketFactory: (maxDaveProtocolVersion) => DiscordVoiceGatewaySocketFactory(
      daveService: maxDaveProtocolVersion > 0
          ? (dave ??= NativeDaveService.open())
          : null,
    ),
  );
  await worker.run(inbox);
  frames?.close();
  inbox.close();
}

/// The encoder's pictures, delivered to this isolate by the native module.
///
/// The address is what the encoder is opened with, in place of the main
/// isolate's own listener. Every picture is also echoed to the main isolate,
/// where the clip buffer keeps recording the stream as it always did.
final class _NativeFrameSource {
  _NativeFrameSource._(this._bindings, this._relay);

  static _NativeFrameSource? open(SendPort relay) {
    try {
      return _NativeFrameSource._(
        NativeVideoBindings(DynamicLibrary.open('flucord_video.dll')),
        relay,
      );
    } on Object {
      // No module: a build that cannot encode has no frames to deliver, and
      // the encoder keeps them in-process.
      return null;
    }
  }

  final NativeVideoBindings _bindings;
  final SendPort _relay;
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();
  late final NativeCallable<NativeFrameCallback> _callable =
      NativeCallable<NativeFrameCallback>.listener(_onFrame);

  Stream<EncodedVideoFrame> get frames => _frames.stream;

  int get address => _callable.nativeFunction.address;

  void _onFrame(
    Pointer<Void> userData,
    Pointer<Uint8> data,
    int length,
    int timestampUs,
    int isKeyframe,
  ) {
    try {
      if (length <= 0 || _frames.isClosed) return;
      final bytes = Uint8List.fromList(data.asTypedList(length));
      _frames.add(
        EncodedVideoFrame(
          bytes: bytes,
          timestamp: Duration(microseconds: timestampUs),
          isKeyframe: isKeyframe != 0,
        ),
      );
      _relay.send(
        MediaFrame(
          bytes: TransferableTypedData.fromList([bytes]),
          timestampUs: timestampUs,
          isKeyframe: isKeyframe != 0,
        ),
      );
    } finally {
      _bindings.releaseFrame(data);
    }
  }

  void close() {
    _callable.close();
    unawaited(_frames.close());
  }
}
