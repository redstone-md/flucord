import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_stream_audio_sender.dart';
import '../data/discord/go_live_media_plane.dart';
import '../data/video/system_audio_capture.dart';
import '../domain/go_live_media.dart';
import '../domain/go_live_stream.dart';
import '../domain/video_capture_hub.dart';
import '../domain/video_encoder.dart';
import '../domain/voice_audio.dart';
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
///
/// The pictures are not sent from here. The media plane opens the share's
/// connection and sends on it from wherever it runs; this controller runs
/// the capture and the sound on the main isolate, and does for the encoder
/// what the far end's feedback asks of it.
final class GoLiveController extends ChangeNotifier {
  GoLiveController({
    required GoLiveRepository? Function() repositoryProvider,
    required VideoCaptureHub capture,

    /// Where the share is sent from. In-process unless told otherwise, which
    /// is what a test wants; the app hands over its media isolate.
    GoLiveMediaPlane? media,
    SystemAudioCapture systemAudio = const UnavailableSystemAudioCapture(),
    VoiceOpusCodecFactory? opusCodecFactory,
    Duration pingInterval = const Duration(seconds: 30),
  }) : _repositoryProvider = repositoryProvider,
       _capture = capture,
       _media = media ?? InProcessGoLiveMediaPlane(frames: capture.frames),
       _systemAudio = systemAudio,
       _opusCodecFactory = opusCodecFactory,
       _pingInterval = pingInterval {
    _mediaSubscriptions = [
      _media.encoderCommands.listen(_applyEncoderCommand),
      _media.paceLines.listen(_logPace),
      _media.relayedFrames.listen(capture.relay),
    ];
  }

  final GoLiveRepository? Function() _repositoryProvider;

  /// The machine's one capture and encode resource. The share is one of its
  /// clients: the camera and the clip buffer draw on it too, and only one of
  /// the three can capture at a time.
  final VideoCaptureHub _capture;

  /// Where the share is sent from.
  final GoLiveMediaPlane _media;

  /// The sound of what is being shared, and what encodes it. Without an
  /// encoder the share is silent, which is what a build without Opus can do.
  final SystemAudioCapture _systemAudio;
  final VoiceOpusCodecFactory? _opusCodecFactory;

  final Duration _pingInterval;

  late final List<StreamSubscription<Object?>> _mediaSubscriptions;

  GoLiveRepository? _repository;
  StreamSubscription<GoLiveStream>? _updates;
  StreamSubscription<GoLiveServer>? _servers;
  Timer? _ping;
  bool _bound = false;
  bool _disposed = false;

  GoLiveStreamKey? _key;
  GoLiveStatus _status = GoLiveStatus.idle;
  GoLiveServer? _server;
  List<String> _viewerIds = const [];
  Object? _error;

  DiscordStreamAudioSender? _audio;
  VoiceOpusEncoder? _audioEncoder;

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

  /// Brings a running share to what the quality setting says now.
  ///
  /// A bitrate alone changes on the running encoder. A new size or frame
  /// rate restarts the capture, because an encoder is built for one shape;
  /// the connection stays up (the encoder's frames reach it across a
  /// restart), the new shape is announced, and the timestamps carry on from
  /// where the old encoder's stopped. Nothing to do when this controller has
  /// no capture running: the next start reads the setting itself. A share
  /// still connecting counts, since it goes live with whatever the capture
  /// runs at by then.
  Future<void> applyQuality() async {
    if (!_captureStarted) return;
    final running = _capture.settings;
    if (running == null) return;
    final wanted = _capture.shareSettings.onSource(running.displayIndex);
    if (running == wanted) return;
    if (running.hasShapeOf(wanted)) {
      _media.retarget(wanted.bitrate);
      _bitrateRefused = false;
      await _capture.setBitrate(wanted.bitrate);
      return;
    }
    try {
      await _capture.stop();
      await _startCapture(running.displayIndex);
    } on Object catch (error) {
      _diagnose('quality change refused', error);
      _error = error;
      _notify();
      return;
    }
    _media.announce(wanted);
    _bitrateRefused = false;
    _diagnose(
      'quality',
      '${wanted.width}x${wanted.height}@${wanted.framesPerSecond} '
          '${wanted.bitrate ~/ 1000}k',
    );
  }

  /// An encoder that cannot change rate is logged once; the sender's pace
  /// follows regardless, since spreading the same bytes thinner is still
  /// less loss than bursting them.
  bool _bitrateRefused = false;

  void _applyEncoderCommand(GoLiveEncoderCommand command) {
    switch (command) {
      case GoLiveKeyframeCommand():
        unawaited(_capture.requestKeyframe());
      case GoLiveBitrateCommand(:final bitsPerSecond):
        unawaited(
          _capture.setBitrate(bitsPerSecond).then((accepted) {
            if (accepted || _bitrateRefused) return;
            _bitrateRefused = true;
            _diagnose(
              'bitrate',
              'encoder keeps its rate; only the pace follows',
            );
          }),
        );
    }
  }

  /// The sender's line about the last few seconds, with the per-frame cost
  /// of each native stage added: a slow frame rate then names its own
  /// bottleneck, and a healthy one points past this machine.
  VideoEncoderDiagnostics? _stage;

  void _logPace(String line) {
    final was = _stage;
    final now = _capture.diagnostics;
    _stage = now;
    final stages = _stageLine(was, now);
    _diagnose('pace', stages == null ? line : '$line, $stages');
  }

  /// The per-frame cost of each native stage over the window, or null when
  /// the platform has nothing to say or no frame went through.
  static String? _stageLine(
    VideoEncoderDiagnostics? was,
    VideoEncoderDiagnostics? now,
  ) {
    if (was == null || now == null) return null;
    final frames = now.frames - was.frames;
    if (frames <= 0) return null;
    int micros(int deltaNs) => deltaNs ~/ frames ~/ 1000;
    return '${now.encoderName}, '
        'wait ${micros(now.captureWaitNs - was.captureWaitNs)}us, '
        'convert ${micros(now.convertNs - was.convertNs)}us, '
        'encode ${micros(now.encodeNs - was.encodeNs)}us';
  }

  bool get isStreaming =>
      _status == GoLiveStatus.live || _status == GoLiveStatus.paused;

  /// Whether there is a share to end: one that is up, or one on its way up.
  ///
  /// A tile that waited for [isStreaming] would offer nothing to stop during
  /// the seconds Discord takes to answer a create frame.
  bool get isSharing =>
      isStreaming ||
      _status == GoLiveStatus.creating ||
      _status == GoLiveStatus.connecting;

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
      await _startCapture(GoLiveDisplay.displayIndexFor(sourceId));
      _captureStarted = true;
      _bitrateRefused = false;
      _stage = null;
      await _startAudio();
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

  /// The display capture, delivering to the media plane when it can take
  /// frames natively and to the hub's stream otherwise.
  Future<void> _startCapture(int displayIndex) async {
    await _capture.startShare(
      displayIndex: displayIndex,
      nativeFrameSink: await _media.nativeFrameSink,
    );
  }

  /// The shared sound, when this build can capture and encode it. A machine
  /// with no output device shares a silent picture rather than no picture.
  Future<void> _startAudio() async {
    final factory = _opusCodecFactory;
    if (factory == null || !_systemAudio.isSupported) return;
    final encoder = _audioEncoder = factory.createEncoder();
    _audio = DiscordStreamAudioSender(
      encoder: encoder,
      sendOpus: _media.sendAudio,
    )..attach(_systemAudio.chunks);
    if (!await _systemAudio.start()) {
      _diagnose('audio', 'no output to share');
    } else if (!_systemAudio.excludesOwnSound) {
      _diagnose('audio', 'own sound included; viewers in the room hear back');
    }
  }

  Future<void> _stopAudio() async {
    _audio?.stop();
    _audio = null;
    await _systemAudio.stop();
    _audioEncoder?.dispose();
    _audioEncoder = null;
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
    for (final subscription in _mediaSubscriptions) {
      unawaited(subscription.cancel());
    }
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
    await _stopAudio();
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
