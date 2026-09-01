import 'dart:async';
import 'dart:typed_data';

import '../../app_log.dart';
import '../../domain/go_live_media.dart';
import '../../domain/stream_bitrate_adapter.dart';
import '../../domain/video_encoder.dart';
import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import 'discord_video_stream_transport.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_gateway_protocol.dart';

/// Where a sender's connection is in its life.
enum GoLiveSenderStatus {
  /// The endpoint is being dialled.
  dialling,

  /// The transport is up and the stream is announced and being sent.
  ready,

  /// The transport went down (a reconnect); pictures and sound are held
  /// until it comes back.
  held,

  failed,
  closed,
}

/// This account's stream, sent on the connection Discord handed out for it.
///
/// Opened once per sender endpoint with everything a sender needs, and from
/// then on it runs by itself: it announces the stream on its own ready, sends
/// the encoder's pictures, and answers what the media server says back. Only
/// what the encoder must do about it leaves, as a [GoLiveEncoderCommand].
/// The wire client underneath is an implementation detail; where the sender
/// runs (the media isolate in the app, in-process in tests) is the plane's
/// decision.
abstract interface class GoLiveSender {
  GoLiveSenderStatus get status;

  Stream<GoLiveSenderStatus> get statuses;

  /// What the far end's feedback asks of the encoder.
  Stream<GoLiveEncoderCommand> get encoderCommands;

  /// One line every few seconds about what the stream is sending.
  Stream<String> get paceLines;

  /// The settings the capture runs at now. A bitrate alone retargets the
  /// pace; a new shape is announced on the running connection.
  void reshape(VideoEncoderSettings settings);

  /// One 20 ms Opus frame of the screen-share audio.
  void sendOpusFrame(Uint8List opus);

  Future<void> close();
}

/// The sender over a wire client, wherever that client runs.
final class GoLiveWireSender implements GoLiveSender {
  GoLiveWireSender({
    required DiscordVoiceClient client,
    required Stream<EncodedVideoFrame> frames,
    required VideoEncoderSettings settings,
    Duration paceInterval = const Duration(seconds: 5),
    DateTime Function() now = DateTime.now,
  }) : _client = client,
       _frames = frames,
       _settings = settings,
       _now = now,
       _windowStarted = now() {
    _events = client.events.listen(_onEvent);
    _pace = Timer.periodic(paceInterval, (_) {
      final line = takePaceLine();
      if (line != null) _paceLines.add(line);
    });
    unawaited(_dial());
  }

  static const _scope = 'golive.media';

  final DiscordVoiceClient _client;
  final Stream<EncodedVideoFrame> _frames;
  final DateTime Function() _now;

  final StreamController<GoLiveSenderStatus> _statuses =
      StreamController.broadcast();
  final StreamController<GoLiveEncoderCommand> _commands =
      StreamController.broadcast();
  final StreamController<String> _paceLines = StreamController.broadcast();

  late final StreamSubscription<VoiceSignalingEvent> _events;
  late final Timer _pace;
  DiscordVideoStreamTransport? _transport;
  StreamBitrateAdapter? _bitrate;
  int? _ssrc;
  int? _videoSsrc;

  /// What the capture runs at, and what of it Discord was last told.
  VideoEncoderSettings _settings;
  VideoEncoderSettings? _announced;

  GoLiveSenderStatus _status = GoLiveSenderStatus.dialling;

  /// Whether the transport is up: set on ready, cleared on any lesser status.
  /// Audio and video are held while it is false so a reconnect does not throw
  /// a frame at a torn-down cipher.
  bool get _ready => _status == GoLiveSenderStatus.ready;

  @override
  GoLiveSenderStatus get status => _status;

  @override
  Stream<GoLiveSenderStatus> get statuses => _statuses.stream;

  @override
  Stream<GoLiveEncoderCommand> get encoderCommands => _commands.stream;

  @override
  Stream<String> get paceLines => _paceLines.stream;

  Future<void> _dial() async {
    try {
      await _client.connect();
    } on Object catch (error) {
      AppLog.error(_scope, 'dial failed', error: error);
      _setStatus(GoLiveSenderStatus.failed);
    }
  }

  void _setStatus(GoLiveSenderStatus status) {
    if (_status == status || _status == GoLiveSenderStatus.closed) return;
    _status = status;
    _statuses.add(status);
  }

  /// Declares the stream and, the first time, starts sending it.
  ///
  /// The order matters: a packet whose SSRC was never announced is dropped on
  /// Discord's side, so the transport is attached only once the announce has
  /// gone out. A watcher decodes nothing until a keyframe, and the encoder's
  /// first one left long before the connection was ready, so one is asked
  /// for at once rather than waited for.
  void _announce() {
    final ssrc = _ssrc;
    if (ssrc == null || !_ready) return;
    final settings = _settings;
    _client.announceVideo(enabled: true, settings: settings);
    _announced = settings;
    final videoSsrc = DiscordVoiceGatewayProtocol.videoSsrcFor(ssrc);
    // A reconnect can hand out a new SSRC, and a transport keeps sending on
    // the one it was built with: frames on a stale SSRC are dropped by the
    // server. When it changed, the old transport is torn down and a new one
    // built for the new numbering.
    if (_transport != null && videoSsrc != _videoSsrc) {
      unawaited(_transport!.stop());
      _transport = null;
    }
    if (_transport == null) {
      _videoSsrc = videoSsrc;
      _transport = DiscordVideoStreamTransport(
        ssrc: videoSsrc,
        rtxSsrc: DiscordVoiceGatewayProtocol.rtxSsrcFor(ssrc),
        // Gated on readiness: during a reconnect the transport cipher is gone,
        // and a frame pushed through then throws, which the transport treats
        // as a dead socket and stops for good. Dropped instead, the stream
        // resumes when the connection comes back.
        sink: (frame) => _ready ? _client.sendVideoFrame(frame) : 0,
        groupEncryptor: (frame) {
          final cipher = _client.encryptVideoForGroup(
            ssrc: videoSsrc,
            frame: frame,
          );
          final passthrough = cipher.length == frame.length;
          if (passthrough != _wasPassthrough) {
            _wasPassthrough = passthrough;
            AppLog.warning(
              _scope,
              'frames now ${passthrough ? 'PASSTHROUGH (no group key yet)' : 'group-encrypted'}',
            );
          }
          return cipher;
        },
        pacingBitsPerSecond: settings.bitrate,
        now: _now,
      )..attach(_countingFrames(_frames));
      _commands.add(const GoLiveKeyframeCommand());
    }
    _retarget(settings.bitrate);
  }

  /// The adapter is retargeted, never recreated: what the link taught it
  /// about loss survives a settings change and a reconnect.
  void _retarget(int bitrate) {
    final adapter = (_bitrate ??= StreamBitrateAdapter(target: bitrate))
      ..retarget(bitrate);
    _transport?.pacingBitsPerSecond = adapter.bitrate;
  }

  @override
  void reshape(VideoEncoderSettings settings) {
    final announced = _announced;
    _settings = settings;
    // Not announced yet: ready will announce whatever the capture runs at
    // by then.
    if (announced == null) return;
    if (announced.hasShapeOf(settings)) {
      _announced = settings;
      _retarget(settings.bitrate);
      return;
    }
    _announce();
  }

  bool _wasPassthrough = false;
  int _keyframesSent = 0;

  /// The frames the transport sends, tapped to count keyframes for the pace
  /// line: a watcher decodes nothing until an IDR, so a window with none is
  /// worth seeing.
  Stream<EncodedVideoFrame> _countingFrames(Stream<EncodedVideoFrame> frames) =>
      frames.map((frame) {
        if (frame.isKeyframe) _keyframesSent++;
        return frame;
      });

  /// Through the connection's own audio path, which encrypts for the group
  /// and declares the speaking state as a call does. A connection without one
  /// (a test double) carries no sound.
  ///
  /// Dropped until the transport is ready: the capture starts producing sound
  /// the moment the stream does, well before the endpoint answered, and the
  /// audio path throws on a frame sent before then.
  @override
  void sendOpusFrame(Uint8List opus) {
    if (!_ready) return;
    if (_client case final VoiceAudioTransport audio) audio.sendOpusFrame(opus);
  }

  @override
  Future<void> close() async {
    if (_status == GoLiveSenderStatus.closed) return;
    _pace.cancel();
    await _events.cancel();
    await _transport?.stop();
    _transport = null;
    await _client.close();
    _setStatus(GoLiveSenderStatus.closed);
    await _statuses.close();
    await _commands.close();
    await _paceLines.close();
  }

  void _onEvent(VoiceSignalingEvent event) {
    switch (event) {
      case VoiceTransportReadyEvent(:final session):
        _ssrc = session.ssrc;
        _setStatus(GoLiveSenderStatus.ready);
        _announce();
      case VoiceSignalingStatusEvent(:final status, :final error):
        AppLog.warning(_scope, status.name, error: error);
        if (status == VoiceConnectionStatus.failure) {
          _setStatus(GoLiveSenderStatus.failed);
        } else if (status != VoiceConnectionStatus.ready && _ready) {
          // The transport cipher is gone; audio and video hold until the
          // connection announces ready again.
          _setStatus(GoLiveSenderStatus.held);
        }
      case VoiceRetransmitRequestedEvent(:final sequences):
        _nacked += sequences.length;
        _transport?.retransmit(sequences);
      case VoiceReceiverReportEvent(:final lossRatio):
        _lossRatio = lossRatio;
        _reports++;
        final next = _bitrate?.report(lossRatio);
        if (next != null) {
          _transport?.pacingBitsPerSecond = next;
          _commands.add(GoLiveBitrateCommand(next));
        }
      case VoiceKeyframeRequestedEvent():
        _pictureLosses++;
        _commands.add(const GoLiveKeyframeCommand());
      default:
        break;
    }
  }

  // The window the next pace line describes: what the far end reported, and
  // where the send counters stood when the last line was taken.
  double _lossRatio = 0;
  int _reports = 0;
  int _nacked = 0;
  int _pictureLosses = 0;
  int _lastFrames = 0;
  int _lastPackets = 0;
  int _lastRetransmitted = 0;
  DateTime _windowStarted;
  bool _stopReported = false;

  /// What the stream sent since the last line, or null before it sends.
  ///
  /// "A stream is slow" has three culprits (the encoder, this sender, the
  /// server) and no way to tell them apart from a watcher's impression. The
  /// line splits the path: the rate that left this machine, what the far end
  /// said about it, the longest wait for a picture and the deepest the pacing
  /// queue got. A transport that stopped says why, once.
  String? takePaceLine() {
    final transport = _transport;
    if (transport == null) return null;
    final now = _now();
    final seconds = now.difference(_windowStarted).inMilliseconds / 1000;
    _windowStarted = now;
    final frames = transport.sentFrames - _lastFrames;
    final packets = transport.sentPackets - _lastPackets;
    final retransmitted = transport.retransmittedPackets - _lastRetransmitted;
    _lastFrames = transport.sentFrames;
    _lastPackets = transport.sentPackets;
    _lastRetransmitted = transport.retransmittedPackets;
    final window = transport.takeWindow();
    final bitrate = _bitrate;
    final error = transport.error;

    String rate(int count) =>
        (seconds <= 0 ? 0 : count / seconds).toStringAsFixed(1);
    final line = [
      '${rate(frames)} frames/s',
      '${rate(packets)} packets/s',
      _describeFeedback(retransmitted),
      'gap ${window.maxSendGap.inMilliseconds}ms',
      'queue ${window.maxQueued}',
      'kf $_keyframesSent',
      if (bitrate != null && bitrate.isAdapted)
        'bitrate ${bitrate.bitrate ~/ 1000}k',
      if (error != null && !_stopReported) 'stopped: $error',
    ].join(', ');
    if (error != null) _stopReported = true;
    _lossRatio = 0;
    _reports = 0;
    _nacked = 0;
    _pictureLosses = 0;
    return line;
  }

  /// "healthy" when the far end said nothing is wrong.
  String _describeFeedback(int retransmitted) {
    if (_reports == 0 && _nacked == 0 && _pictureLosses == 0) return 'healthy';
    return [
      if (_reports > 0) '${(_lossRatio * 100).toStringAsFixed(1)}% loss',
      if (_nacked > 0) '$retransmitted/$_nacked resent',
      if (_pictureLosses > 0) '$_pictureLosses keyframe req',
    ].join(', ');
  }
}
