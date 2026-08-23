import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_video_stream_transport.dart';
import '../domain/go_live_stream.dart';
import '../domain/video_capture_hub.dart';
import '../app_log.dart';

/// A display this machine can share.
///
/// Named by the encoder rather than by a capture library: enumerating sources
/// through WebRTC opens duplications of its own to build thumbnails with, and
/// one of those left open is what refuses the share afterwards.
final class GoLiveDisplay {
  const GoLiveDisplay({required this.index, required this.name});

  final int index;
  final String name;

  /// The id a picked screen travels as, `screen:<index>:<n>`, which is the
  /// shape a capture source list uses. This client never varies the tail, but
  /// the shape is not ours to change.
  String get sourceId => 'screen:$index:0';

  /// Which display a source id names, or the primary when it names none.
  ///
  /// A window, or a name this client does not make, is the primary display:
  /// the capture takes it by default, and refusing a share over a shape
  /// nobody here writes would be inventing a failure.
  static int displayIndexFor(String? sourceId) {
    if (sourceId == null || !sourceId.startsWith('screen:')) return 0;
    final index = int.tryParse(sourceId.split(':').elementAtOrNull(1) ?? '');
    if (index == null || index < 0) return 0;
    return index;
  }
}

/// Drives Go Live: opening a stream, holding it alive, and ending it.
///
/// The stream is a second RTC connection alongside the voice one, so this is a
/// controller of its own rather than a mode of the voice controller: ending a
/// stream must not disturb the call it is inside.
final class GoLiveController extends ChangeNotifier {
  GoLiveController({
    required GoLiveRepository? Function() repositoryProvider,
    required VideoCaptureHub capture,
    Duration pingInterval = const Duration(seconds: 30),
  }) : _repositoryProvider = repositoryProvider,
       _capture = capture,
       _pingInterval = pingInterval;

  final GoLiveRepository? Function() _repositoryProvider;

  /// The machine's one capture and encode resource. The share is one of its
  /// clients: the camera and the clip buffer draw on it too, and only one of
  /// the three can capture at a time.
  final VideoCaptureHub _capture;

  final Duration _pingInterval;

  DiscordVideoStreamTransport? _transport;

  GoLiveRepository? _repository;
  StreamSubscription<GoLiveStream>? _updates;
  StreamSubscription<GoLiveServer>? _servers;
  Timer? _ping;
  Timer? _paceLog;
  bool _bound = false;
  bool _disposed = false;

  GoLiveStreamKey? _key;
  GoLiveStatus _status = GoLiveStatus.idle;
  GoLiveServer? _server;
  List<String> _viewerIds = const [];
  Object? _error;

  bool get isSupported {
    _bind();
    return _repository != null;
  }

  GoLiveStatus get status => _status;
  GoLiveStreamKey? get streamKey => _key;

  /// Who is watching this account's stream.
  List<String> get viewerIds => _viewerIds;

  /// The RTC endpoint Discord assigned, once it has.
  GoLiveServer? get server => _server;

  /// Whether this build can send pictures at all.
  bool get canEncode => _capture.isSupported;

  /// How many RTP packets the picture has taken so far, which is what tells a
  /// caller the stream is moving rather than merely open.
  int get sentPackets => _transport?.sentPackets ?? 0;

  /// Why sending stopped, if it did.
  Object? get transportError => _transport?.error;

  /// Points the capture's output at a stream connection.
  ///
  /// Called once the RTC side has an SSRC and somewhere to send: the capture
  /// runs from the moment the stream opens, but its frames go nowhere until
  /// there is a socket to take them.
  void bindTransport({
    required int ssrc,
    required VideoFrameSink sink,
    VideoFrameGroupEncryptor? groupEncryptor,
  }) {
    _transport?.stop();
    _transport = DiscordVideoStreamTransport(
      ssrc: ssrc,
      sink: sink,
      groupEncryptor: groupEncryptor,
    )..attach(_capture.frames);
    _startPaceLog();
  }

  /// Says what the stream is actually sending, every few seconds.
  ///
  /// "A stream is slow" has three different culprits (the encoder, this
  /// client, the server) and no way to tell them apart from a viewer's
  /// impression. The numbers here split the path in two: if the frame rate
  /// that left this machine is the configured one, whatever a viewer sees is
  /// happening beyond this socket.
  void _startPaceLog() {
    _paceLog?.cancel();
    var frames = _transport?.sentFrames ?? 0;
    var packets = _transport?.sentPackets ?? 0;
    _paceLog = Timer.periodic(const Duration(seconds: 5), (_) {
      final transport = _transport;
      if (transport == null) return;
      final nextFrames = transport.sentFrames;
      final nextPackets = transport.sentPackets;
      _diagnose(
        'pace',
        '${(nextFrames - frames) / 5} frames/s, '
            '${(nextPackets - packets) / 5} packets/s',
      );
      frames = nextFrames;
      packets = nextPackets;
    });
  }

  bool get isStreaming =>
      _status == GoLiveStatus.live || _status == GoLiveStatus.paused;

  Object? get error => _error;

  /// The displays this machine can share.
  List<GoLiveDisplay> get displays => [
    for (var index = 0; index < _capture.displayCount; index++)
      GoLiveDisplay(index: index, name: 'Screen ${index + 1}'),
  ];

  /// Attaches to the active transport.
  void reconcile() => _bind();

  /// Starts sharing [sourceId] into the voice channel on screen.
  ///
  /// A null [sourceId] shares the primary screen, which is what the button in
  /// the room does — and what the platform resolves for itself. Naming a
  /// screen from a list read earlier is what failed with "that display is no
  /// longer attached"; the invented "0" before it failed with "source not
  /// found".
  // Whether the capture behind this stream is the stream's to stop: the
  // module is shared, and stopping what another client is running (the
  // camera's session, when a share was refused) would tear down somebody
  // else's picture on the way out.
  bool _captureStarted = false;

  Future<bool> start({
    required String channelId,
    String? sourceId,
    String? guildId,
  }) async {
    _bind();
    final repository = _repository;
    if (repository == null || _status != GoLiveStatus.idle) return false;
    _status = GoLiveStatus.creating;
    _error = null;
    _notify();
    try {
      // The capture is what produces the picture Discord receives: the one
      // module reads the display itself, through Desktop Duplication, and
      // nothing else in the client opens a duplication of its own. Windows
      // refuses the second with E_INVALIDARG, which is what the room used
      // to report as "that display is no longer attached".
      await _capture.startShare(
        displayIndex: GoLiveDisplay.displayIndexFor(sourceId),
      );
      _captureStarted = true;
      _key = await repository.startStream(
        channelId: channelId,
        guildId: guildId,
      );
      // Discord's own clients follow the create with an unpause. Attempted
      // rather than required: a server that refuses it has not refused the
      // stream, and failing the share over it would be inventing a problem.
      try {
        await repository.setPaused(_key!, paused: false);
      } on Object catch (error) {
        _diagnose('unpause refused', error);
      }
      _diagnose('started', sourceId ?? 'primary screen');
      _startPinging();
      return true;
    } on Object catch (error) {
      _diagnose('start failed', error);
      _error = error;
      _status = GoLiveStatus.failure;
      await _stopCapture();
      return false;
    } finally {
      _notify();
    }
  }

  /// Holds frames back without tearing the stream down.
  Future<bool> setPaused({required bool paused}) async {
    final repository = _repository;
    final key = _key;
    if (repository == null || key == null || !isStreaming) return false;
    try {
      await repository.setPaused(key, paused: paused);
      // The capture stops producing too: pausing that only told Discord would
      // keep burning the CPU on frames nobody receives.
      await _capture.setPaused(paused: paused);
      _status = paused ? GoLiveStatus.paused : GoLiveStatus.live;
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _notify();
    }
  }

  /// Ends the stream and stops the capture behind it.
  Future<void> stop() async {
    final repository = _repository;
    final key = _key;
    _ping?.cancel();
    _ping = null;
    if (repository != null && key != null) {
      try {
        await repository.endStream(key);
      } on Object catch (error) {
        _error = error;
      }
    }
    await _stopCapture();
    _key = null;
    _server = null;
    _viewerIds = const [];
    if (_status != GoLiveStatus.failure) _status = GoLiveStatus.idle;
    _notify();
  }

  /// Watches somebody else's stream.
  Future<bool> watch(GoLiveStreamKey key) async {
    _bind();
    final repository = _repository;
    if (repository == null) return false;
    try {
      await repository.watchStream(key);
      return true;
    } on Object catch (error) {
      _error = error;
      _notify();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ping?.cancel();
    _ping = null;
    _paceLog?.cancel();
    _paceLog = null;
    unawaited(_updates?.cancel());
    unawaited(_servers?.cancel());
    super.dispose();
  }

  void _startPinging() {
    _ping?.cancel();
    // Discord drops a stream that stops reporting in, so the ping runs for as
    // long as the stream does rather than being sent once at the start.
    _ping = Timer.periodic(_pingInterval, (_) {
      final repository = _repository;
      final key = _key;
      if (repository != null && key != null) {
        unawaited(repository.pingStream(key));
      }
    });
  }

  Future<void> _stopCapture() async {
    _paceLog?.cancel();
    _paceLog = null;
    await _transport?.stop();
    _transport = null;
    if (!_captureStarted) return;
    _captureStarted = false;
    try {
      await _capture.stop();
    } on Object catch (_) {
      // Already stopped. Not worth reporting over whatever ended the stream.
    }
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_updates?.cancel());
    unawaited(_servers?.cancel());
    _repository = repository;
    _updates = repository?.updates.listen(_acceptStream);
    _servers = repository?.servers.listen(_acceptServer);
    return true;
  }

  void _acceptStream(GoLiveStream stream) {
    if (stream.key != _key) return;
    _viewerIds = stream.viewerIds;
    if (_status == GoLiveStatus.creating) _status = GoLiveStatus.connecting;
    if (isStreaming) {
      _status = stream.isPaused ? GoLiveStatus.paused : GoLiveStatus.live;
    }
    _notify();
  }

  void _acceptServer(GoLiveServer server) {
    if (server.key != _key) return;
    _server = server;
    // The endpoint is the last thing needed before frames can go anywhere.
    if (_status == GoLiveStatus.creating ||
        _status == GoLiveStatus.connecting) {
      _status = GoLiveStatus.live;
    }
    _notify();
  }

  void _diagnose(String what, [Object? detail]) {
    AppLog.warning('golive', '$what${detail == null ? '' : ': $detail'}');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
