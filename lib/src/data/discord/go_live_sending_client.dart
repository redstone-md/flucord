import 'dart:async';
import 'dart:typed_data';

import '../../app_log.dart';
import '../../domain/go_live_media.dart';
import '../../domain/stream_bitrate_adapter.dart';
import '../../domain/video_encoder.dart';
import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import 'discord_rtp_packet.dart';
import 'discord_video_stream_transport.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_gateway_protocol.dart';

/// A stream connection that sends this machine's share by itself.
///
/// In front of the connection Discord handed out for the share, doing what a
/// sender does: once the share is announced, the encoder's pictures are
/// packetised, paced and sent on it, and what the media server says back —
/// the packets a viewer missed, the loss it saw, the keyframes it needs — is
/// answered here. Only what the encoder must do about it leaves, as a
/// [GoLiveEncoderCommand]. Everything a share sends therefore runs wherever
/// the connection runs: on the main isolate in tests, on the media isolate in
/// the app, where a busy UI cannot hold a picture back.
final class GoLiveSendingClient implements DiscordVoiceClient, GoLiveSender {
  GoLiveSendingClient({
    required DiscordVoiceClient inner,
    required Stream<EncodedVideoFrame> frames,
    required void Function(GoLiveEncoderCommand command) onEncoderCommand,
    this.onClosed,
    DateTime Function() now = DateTime.now,
  }) : _inner = inner,
       _frames = frames,
       _onEncoderCommand = onEncoderCommand,
       _now = now,
       _windowStarted = now() {
    _events = inner.events.listen(_onEvent);
    // A share sends, but its socket still has to be drained: the media
    // server's RTCP — the loss it saw, the packets a viewer missed, the
    // keyframes a viewer joining needs (PLI) — arrives on the same socket,
    // and the client only reads it while something listens to its incoming
    // packets. Nothing here wants the packets themselves (a send-only stream
    // receives none), but the act of listening is what pumps the socket and
    // routes the feedback to the events this client acts on. Without it a
    // viewer's PLI never arrives, no fresh keyframe is sent, and the stream
    // never loads for anyone who joined after the first picture.
    _incoming = inner.videoPackets.listen((_) {});
  }

  final DiscordVoiceClient _inner;
  final Stream<EncodedVideoFrame> _frames;
  final void Function(GoLiveEncoderCommand command) _onEncoderCommand;
  final DateTime Function() _now;

  /// Told when the connection was closed, so whoever holds "the current
  /// share connection" can let go of it.
  final void Function()? onClosed;

  late final StreamSubscription<VoiceSignalingEvent> _events;
  late final StreamSubscription<(String, DiscordRtpFrame)> _incoming;
  DiscordVideoStreamTransport? _transport;
  StreamBitrateAdapter? _bitrate;
  int? _ssrc;

  /// Whether the transport is up: set on ready, cleared on any lesser status.
  /// Audio and video are held while it is false so a reconnect does not throw
  /// a frame at a torn-down cipher.
  bool _ready = false;

  /// The transport under the share, or null before the share was announced.
  DiscordVideoStreamTransport? get transport => _transport;

  @override
  Stream<VoiceSignalingEvent> get events => _inner.events;

  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets => _inner.videoPackets;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _inner.remoteAudio;

  @override
  int? get audioSsrc => _inner.audioSsrc;

  @override
  Future<void> connect() => _inner.connect();

  /// Declares the share and, the first time, starts sending it.
  ///
  /// The order matters: a packet whose SSRC was never announced is dropped on
  /// Discord's side, so the transport is attached only once the announce has
  /// gone out. A viewer decodes nothing until a keyframe, and the encoder's
  /// first one left long before the connection was ready, so one is asked
  /// for at once rather than waited for. Announcing again, with a new shape,
  /// makes its bitrate the new target.
  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    final announced = _inner.announceVideo(
      enabled: enabled,
      settings: settings,
    );
    final ssrc = _ssrc;
    if (!enabled || ssrc == null) return announced;
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
        // and a frame pushed through then throws — which the transport treats
        // as a dead socket and stops for good. Dropped instead, the share
        // resumes when the connection comes back.
        sink: (frame) => _ready ? _inner.sendVideoFrame(frame) : 0,
        groupEncryptor: (frame) {
          final cipher = _inner.encryptVideoForGroup(
            ssrc: videoSsrc,
            frame: frame,
          );
          final passthrough = cipher.length == frame.length;
          if (passthrough != _wasPassthrough) {
            _wasPassthrough = passthrough;
            AppLog.warning(
              'golive.media',
              'frames now ${passthrough ? 'PASSTHROUGH (no group key yet)' : 'group-encrypted'}',
            );
          }
          return cipher;
        },
        pacingBitsPerSecond: settings.bitrate,
        now: _now,
      )..attach(_countingFrames(_frames));
      _onEncoderCommand(const GoLiveKeyframeCommand());
    }
    retarget(settings.bitrate);
    return announced;
  }

  @override
  void retarget(int bitrate) {
    _bitrate = StreamBitrateAdapter(target: bitrate);
    _transport?.pacingBitsPerSecond = bitrate;
  }

  bool _wasPassthrough = false;
  int _keyframesSent = 0;
  int? _videoSsrc;

  /// The frames the transport sends, tapped to count keyframes for the pace
  /// line: a viewer decodes nothing until an IDR, so a window with none is
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
  /// the moment the share does, well before the endpoint answered, and the
  /// audio path throws on a frame sent before then — a viewer only hears from
  /// when they join regardless, so an early frame is nothing to keep.
  @override
  void sendOpusFrame(Uint8List opus) {
    if (!_ready) return;
    if (_inner case final VoiceAudioTransport audio) audio.sendOpusFrame(opus);
  }

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) => _inner.encryptVideoForGroup(ssrc: ssrc, frame: frame);

  @override
  int sendVideoFrame(DiscordRtpFrame frame) => _inner.sendVideoFrame(frame);

  @override
  Future<void> close() async {
    await _events.cancel();
    await _incoming.cancel();
    await _transport?.stop();
    _transport = null;
    await _inner.close();
    onClosed?.call();
  }

  void _onEvent(VoiceSignalingEvent event) {
    switch (event) {
      case VoiceTransportReadyEvent(:final session):
        _ssrc = session.ssrc;
        _ready = true;
      case VoiceSignalingStatusEvent(:final status):
        // Anything short of ready means the transport cipher is gone or not
        // yet up; audio and video hold until it comes back.
        if (status != VoiceConnectionStatus.ready) _ready = false;
      case VoiceRetransmitRequestedEvent(:final sequences):
        _nacked += sequences.length;
        _transport?.retransmit(sequences);
      case VoiceReceiverReportEvent(:final lossRatio):
        _lossRatio = lossRatio;
        _reports++;
        final next = _bitrate?.report(lossRatio);
        if (next != null) {
          _transport?.pacingBitsPerSecond = next;
          _onEncoderCommand(GoLiveBitrateCommand(next));
        }
      case VoiceKeyframeRequestedEvent():
        _pictureLosses++;
        _onEncoderCommand(const GoLiveKeyframeCommand());
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

  /// What the share sent since the last line, or null before it sends.
  ///
  /// "A stream is slow" has three culprits (the encoder, this client, the
  /// server) and no way to tell them apart from a viewer's impression. The
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
