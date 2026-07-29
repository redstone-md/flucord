import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_video_stream_transport.dart';
import '../domain/go_live_stream.dart';
import '../domain/video_encoder.dart';
import '../domain/voice_media.dart';

/// Drives Go Live: opening a stream, holding it alive, and ending it.
///
/// The stream is a second RTC connection alongside the voice one, so this is a
/// controller of its own rather than a mode of the voice controller: ending a
/// stream must not disturb the call it is inside.
final class GoLiveController extends ChangeNotifier {
  GoLiveController({
    required GoLiveRepository? Function() repositoryProvider,
    required VoiceMediaService mediaService,
    VideoEncoderService? encoder,
    VideoEncoderSettings settings = const VideoEncoderSettings(),
    Duration pingInterval = const Duration(seconds: 30),
  }) : _repositoryProvider = repositoryProvider,
       _mediaService = mediaService,
       _encoder = encoder,
       _settings = settings,
       _pingInterval = pingInterval;

  final GoLiveRepository? Function() _repositoryProvider;
  final VoiceMediaService _mediaService;

  /// Turns the display into H.264. Null on a build without the native module,
  /// where a stream can still be opened and watched but not sent.
  final VideoEncoderService? _encoder;

  final VideoEncoderSettings _settings;
  final Duration _pingInterval;

  DiscordVideoStreamTransport? _transport;

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
  Object? _previewError;

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
  bool get canEncode => _encoder?.isSupported ?? false;

  /// How many RTP packets the picture has taken so far, which is what tells a
  /// caller the stream is moving rather than merely open.
  int get sentPackets => _transport?.sentPackets ?? 0;

  /// Why sending stopped, if it did.
  Object? get transportError => _transport?.error;

  /// Points the encoder's output at a stream connection.
  ///
  /// Called once the RTC side has an SSRC and somewhere to send: the encoder
  /// runs from the moment the stream opens, but its frames go nowhere until
  /// there is a socket to take them.
  void bindTransport({required int ssrc, required VideoFrameSink sink}) {
    final encoder = _encoder;
    if (encoder == null) return;
    _transport?.stop();
    _transport = DiscordVideoStreamTransport(ssrc: ssrc, sink: sink)
      ..attach(encoder.frames);
  }

  bool get isStreaming =>
      _status == GoLiveStatus.live || _status == GoLiveStatus.paused;

  Object? get error => _error;

  /// Why the local preview is missing while the stream itself is running.
  Object? get previewError => _previewError;

  /// Attaches to the active transport.
  void reconcile() => _bind();

  /// Starts sharing [sourceId] into the voice channel on screen.
  ///
  /// A null [sourceId] shares the primary screen, which is what the button in
  /// the room does — and what the platform resolves for itself. Naming a
  /// screen from a list read earlier is what failed with "that display is no
  /// longer attached"; the invented "0" before it failed with "source not
  /// found".
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
    _previewError = null;
    _notify();
    try {
      // The encoder is what produces the picture Discord receives: it reads
      // the display itself, through Desktop Duplication. The media service's
      // capture only feeds the local preview, so it is attempted rather than
      // required — a preview that will not open is a room without a
      // thumbnail, not a stream nobody can watch. It was aborting the entire
      // share with "that display is no longer attached" while the encoder
      // would have been perfectly happy.
      await _encoder?.start(_settingsFor(sourceId));
      try {
        await _mediaService.startScreenShare(sourceId);
      } on Object catch (error) {
        _previewError = error;
      }
      _key = await repository.startStream(
        channelId: channelId,
        guildId: guildId,
      );
      _diagnose(
        'started',
        '${sourceId ?? 'primary screen'}'
            '${_previewError == null ? '' : ' (no preview: $_previewError)'}',
      );
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

  /// The encoder settings for [sourceId].
  ///
  /// A screen picked from the capturer is named `screen:<index>:<n>`; the
  /// encoder addresses displays by index, so the index is read back out of it.
  /// Anything else — a window, or no choice at all — is the primary display,
  /// which is what the encoder captures by default.
  VideoEncoderSettings _settingsFor(String? sourceId) {
    if (sourceId == null || !sourceId.startsWith('screen:')) return _settings;
    final index = int.tryParse(sourceId.split(':').elementAtOrNull(1) ?? '');
    if (index == null || index < 0) return _settings;
    return _settings.onDisplay(index);
  }

  /// Holds frames back without tearing the stream down.
  Future<bool> setPaused({required bool paused}) async {
    final repository = _repository;
    final key = _key;
    if (repository == null || key == null || !isStreaming) return false;
    try {
      await repository.setPaused(key, paused: paused);
      // The encoder stops producing too: pausing that only told Discord would
      // keep burning the CPU on frames nobody receives.
      await _encoder?.setPaused(paused: paused);
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
    await _transport?.stop();
    _transport = null;
    try {
      await _encoder?.stop();
    } on Object catch (_) {
      // Already stopped. Not worth reporting over whatever ended the stream.
    }
    try {
      await _mediaService.stopScreenShare();
    } on Object catch (_) {
      // Already stopped, or the device went away with the stream. Neither is
      // worth reporting over whatever ended the stream in the first place.
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
    final line = 'flucord.golive $what${detail == null ? '' : ': $detail'}';
    developer.log(line, name: 'flucord.golive', level: 900);
    if (kDebugMode) stdout.writeln(line);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
