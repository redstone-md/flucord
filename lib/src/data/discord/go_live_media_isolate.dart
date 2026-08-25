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
import 'discord_rtp_packet.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_socket_factory.dart';
import 'go_live_media_plane.dart';
import 'go_live_sending_client.dart';

/// The share, sent from an isolate of its own.
///
/// What Discord does with a media thread: the share's whole connection — the
/// signalling socket, the group encryption, the packetiser, the pacer, the
/// transport cipher and the UDP socket — lives on a worker isolate, and the
/// encoder hands its pictures to that isolate directly. The main isolate,
/// which also draws the UI, never holds a picture back: a long build, a
/// garbage collection or a burst of gateway events used to stall the send
/// path for hundreds of milliseconds at a time, and every stall reached the
/// viewer as a freeze followed by a burst.
///
/// The main isolate keeps a proxy per connection, which speaks the client
/// interface the stream plane already dials, and steers the encoder on the
/// worker's behalf through the plane's command stream.
final class GoLiveMediaIsolate implements GoLiveMediaPlane {
  GoLiveMediaIsolate();

  static const _scope = 'golive.media';

  final ReceivePort _inbox = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final Completer<_Hello> _hello = Completer();
  final StreamController<GoLiveEncoderCommand> _commands =
      StreamController.broadcast();
  final StreamController<String> _paceLines = StreamController.broadcast();
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();
  final Map<int, _IsolateSendingClient> _clients = {};

  Future<void>? _spawning;
  int _nextId = 0;
  _IsolateSendingClient? _current;

  @override
  Future<int?> get nativeFrameSink =>
      _worker().then((hello) => hello.frameSink);

  @override
  Stream<GoLiveEncoderCommand> get encoderCommands => _commands.stream;

  @override
  Stream<String> get paceLines => _paceLines.stream;

  @override
  Stream<EncodedVideoFrame> get relayedFrames => _frames.stream;

  @override
  DiscordVoiceClient openSender({
    required DiscordVoiceSocketFactory factory,
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) {
    final id = _nextId++;
    final client = _IsolateSendingClient(id: id, plane: this);
    _clients[id] = client;
    _current = client;
    _post(
      _Open(
        id: id,
        credentials: credentials,
        streamKey: streamKey,
        maxDaveProtocolVersion: factory.maxDaveProtocolVersion,
      ),
    );
    return client;
  }

  @override
  void announce(VideoEncoderSettings settings) =>
      _current?.announceVideo(enabled: true, settings: settings);

  @override
  void retarget(int bitrate) => _current?.retarget(bitrate);

  @override
  void sendAudio(Uint8List opus) => _current?.sendOpusFrame(opus);

  Future<void> dispose() async {
    _post(const _Shutdown());
    for (final client in _clients.values.toList(growable: false)) {
      client.finishClose();
    }
    _clients.clear();
    _current = null;
    _inbox.close();
    _errors.close();
    await _commands.close();
    await _paceLines.close();
    await _frames.close();
  }

  /// The worker, spawned on first use and kept for the process.
  Future<_Hello> _worker() {
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
      case _Hello():
        if (!_hello.isCompleted) _hello.complete(message);
      case _Event(:final id, :final event):
        _clients[id]?.accept(event);
      case _PaceLine(:final line):
        _paceLines.add(line);
      case _Command(:final command):
        _commands.add(command);
      case _Frame(:final bytes, :final timestampUs, :final isKeyframe):
        _frames.add(
          EncodedVideoFrame(
            bytes: bytes.materialize().asUint8List(),
            timestamp: Duration(microseconds: timestampUs),
            isKeyframe: isKeyframe,
          ),
        );
      case _Log(:final level, :final scope, :final message, :final error):
        AppLog.record(level, scope, message, error: error);
      case _Closed(:final id):
        _clients.remove(id)?.finishClose();
    }
  }
}

/// The main isolate's end of one share connection on the worker.
final class _IsolateSendingClient implements DiscordVoiceClient, GoLiveSender {
  _IsolateSendingClient({required this.id, required GoLiveMediaIsolate plane})
    : _plane = plane;

  /// How long a close waits for the worker to confirm before giving up on
  /// it: a worker that died must not hang the stream plane's teardown.
  static const _closeTimeout = Duration(seconds: 3);

  final int id;
  final GoLiveMediaIsolate _plane;
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  int? _audioSsrc;
  Completer<void>? _closing;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  /// A share sends; nothing arrives on its connection to hand out.
  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets =>
      const Stream<(String, DiscordRtpFrame)>.empty();

  @override
  int? get audioSsrc => _audioSsrc;

  @override
  Future<void> connect() async => _plane._post(_Connect(id));

  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    _plane._post(_Announce(id: id, enabled: enabled, settings: settings));
    return true;
  }

  @override
  void retarget(int bitrate) =>
      _plane._post(_Retarget(id: id, bitrate: bitrate));

  @override
  void sendOpusFrame(Uint8List opus) =>
      _plane._post(_Audio(id: id, opus: opus));

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) => throw UnsupportedError('the share is sent from the media isolate');

  @override
  int sendVideoFrame(DiscordRtpFrame frame) =>
      throw UnsupportedError('the share is sent from the media isolate');

  @override
  Future<void> close() async {
    final closing = _closing;
    if (closing != null) return closing.future;
    final completer = _closing = Completer<void>();
    if (identical(_plane._current, this)) _plane._current = null;
    _plane._post(_Close(id));
    await completer.future.timeout(_closeTimeout, onTimeout: () {});
    if (!_events.isClosed) await _events.close();
  }

  void accept(VoiceSignalingEvent event) {
    if (event is VoiceTransportReadyEvent) _audioSsrc = event.session.ssrc;
    if (!_events.isClosed) _events.add(event);
  }

  void finishClose() {
    final closing = _closing;
    if (closing != null && !closing.isCompleted) closing.complete();
  }
}

// What crosses between the isolates. Plain values only: a message with a
// closure or a native handle in it cannot be sent, and the send throws.

final class _Hello {
  const _Hello({required this.port, required this.frameSink});

  final SendPort port;
  final int? frameSink;
}

final class _Open {
  const _Open({
    required this.id,
    required this.credentials,
    required this.streamKey,
    required this.maxDaveProtocolVersion,
  });

  final int id;
  final VoiceServerCredentials credentials;
  final GoLiveStreamKey streamKey;
  final int maxDaveProtocolVersion;
}

final class _Connect {
  const _Connect(this.id);

  final int id;
}

final class _Close {
  const _Close(this.id);

  final int id;
}

final class _Announce {
  const _Announce({
    required this.id,
    required this.enabled,
    required this.settings,
  });

  final int id;
  final bool enabled;
  final VideoEncoderSettings settings;
}

final class _Retarget {
  const _Retarget({required this.id, required this.bitrate});

  final int id;
  final int bitrate;
}

final class _Audio {
  const _Audio({required this.id, required this.opus});

  final int id;
  final Uint8List opus;
}

final class _Shutdown {
  const _Shutdown();
}

final class _Event {
  const _Event({required this.id, required this.event});

  final int id;
  final VoiceSignalingEvent event;
}

final class _PaceLine {
  const _PaceLine(this.line);

  final String line;
}

final class _Command {
  const _Command(this.command);

  final GoLiveEncoderCommand command;
}

final class _Frame {
  const _Frame({
    required this.bytes,
    required this.timestampUs,
    required this.isKeyframe,
  });

  final TransferableTypedData bytes;
  final int timestampUs;
  final bool isKeyframe;
}

final class _Log {
  const _Log({
    required this.level,
    required this.scope,
    required this.message,
    required this.error,
  });

  final AppLogLevel level;
  final String scope;
  final String message;
  final String? error;
}

final class _Closed {
  const _Closed(this.id);

  final int id;
}

// The worker isolate.

Future<void> _workerMain(SendPort toMain) async {
  final inbox = ReceivePort();
  AppLog.redirect = (level, scope, message, error) => toMain.send(
    _Log(
      level: level,
      scope: scope,
      message: message,
      error: error?.toString(),
    ),
  );
  final frames = _NativeFrameSource.open(toMain);
  toMain.send(_Hello(port: inbox.sendPort, frameSink: frames?.address));
  final worker = _Worker(
    toMain: toMain,
    frames: frames?.frames ?? const Stream<EncodedVideoFrame>.empty(),
  );
  await for (final message in inbox) {
    if (message is _Shutdown) break;
    // One bad message must not end the loop: a throw here used to terminate
    // the isolate, and every share after it hung at "dialling" against a
    // worker that no longer read its inbox.
    try {
      worker.handle(message);
    } on Object catch (error, stackTrace) {
      toMain.send(
        _Log(
          level: AppLogLevel.error,
          scope: 'golive.media',
          message: 'message failed',
          error: '$error\n$stackTrace',
        ),
      );
    }
  }
  await worker.closeAll();
  frames?.close();
  inbox.close();
}

/// The connections the worker holds, by the id the main isolate gave them.
final class _Worker {
  _Worker({required SendPort toMain, required Stream<EncodedVideoFrame> frames})
    : _toMain = toMain,
      _frames = frames;

  static const _paceInterval = Duration(seconds: 5);

  final SendPort _toMain;
  final Stream<EncodedVideoFrame> _frames;
  final Map<int, _Connection> _connections = {};
  NativeDaveService? _dave;

  void handle(Object? message) {
    switch (message) {
      case _Open():
        _open(message);
      case _Connect(:final id):
        unawaited(_connections[id]?.client.connect());
      case _Announce(:final id, :final enabled, :final settings):
        _connections[id]?.client.announceVideo(
          enabled: enabled,
          settings: settings,
        );
      case _Retarget(:final id, :final bitrate):
        _connections[id]?.client.retarget(bitrate);
      case _Audio(:final id, :final opus):
        _connections[id]?.client.sendOpusFrame(opus);
      case _Close(:final id):
        unawaited(_close(id));
    }
  }

  void _open(_Open open) {
    final GoLiveSendingClient client;
    try {
      // The same factory the main isolate dials with, built here so that the
      // group encryptor is created, keyed and used on one thread.
      final factory = DiscordVoiceGatewaySocketFactory(
        daveService: open.maxDaveProtocolVersion > 0
            ? (_dave ??= NativeDaveService.open())
            : null,
      );
      client = GoLiveSendingClient(
        inner: factory.streamSocket(
          credentials: open.credentials,
          streamKey: open.streamKey,
        ),
        frames: _frames,
        onEncoderCommand: (command) => _toMain.send(_Command(command)),
      );
    } on Object catch (error) {
      _toMain.send(
        _Event(
          id: open.id,
          event: VoiceSignalingStatusEvent(
            VoiceConnectionStatus.failure,
            error: '$error',
          ),
        ),
      );
      return;
    }
    _connections[open.id] = _Connection(
      client: client,
      events: client.events.listen(
        (event) => _toMain.send(_Event(id: open.id, event: _sendable(event))),
      ),
      pace: Timer.periodic(_paceInterval, (_) {
        final line = client.takePaceLine();
        if (line != null) _toMain.send(_PaceLine(line));
      }),
    );
  }

  Future<void> _close(int id) async {
    await _connections.remove(id)?.close();
    _toMain.send(_Closed(id));
  }

  Future<void> closeAll() async {
    for (final id in _connections.keys.toList(growable: false)) {
      await _close(id);
    }
  }

  /// An event as the other isolate can receive it. A status carries whatever
  /// object failed, and an exception with a socket or an address inside it
  /// may not cross; its text always does.
  static VoiceSignalingEvent _sendable(VoiceSignalingEvent event) {
    if (event is VoiceSignalingStatusEvent && event.error != null) {
      return VoiceSignalingStatusEvent(event.status, error: '${event.error}');
    }
    return event;
  }
}

final class _Connection {
  _Connection({required this.client, required this.events, required this.pace});

  final GoLiveSendingClient client;
  final StreamSubscription<VoiceSignalingEvent> events;
  final Timer pace;

  Future<void> close() async {
    pace.cancel();
    await events.cancel();
    await client.close();
  }
}

/// The encoder's pictures, delivered to this isolate by the native module.
///
/// The address is what the encoder is opened with, in place of the main
/// isolate's own listener. Every picture is also echoed to the main isolate,
/// where the clip buffer keeps recording the share as it always did.
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
        _Frame(
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
