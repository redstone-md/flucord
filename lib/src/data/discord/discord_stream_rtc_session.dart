import 'dart:async';


import '../../domain/go_live_stream.dart';
import '../../domain/voice_connection.dart';
import '../../domain/video_encoder.dart';
import 'discord_rtp_packet.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_socket_factory.dart';
import '../../app_log.dart';

/// One Go Live stream's RTC connection.
///
/// A stream is not carried on the call's connection. Discord answers
/// `STREAM_CREATE` and `STREAM_WATCH` with an endpoint and a token of their
/// own, and the pictures — sent or received — only ever cross that second
/// socket. Everything below the endpoint is the voice transport already in
/// place: the same handshake, the same UDP discovery, the same cipher.
///
/// Which DAVE configuration the socket identifies with is not decided here:
/// the socket factory owns that, one place for both planes.
final class DiscordStreamRtcSession {
  DiscordStreamRtcSession({
    required this.key,
    required VoiceServerCredentials credentials,
    required DiscordVoiceSocketFactory socketFactory,
  }) : _credentials = credentials,
       _socketFactory = socketFactory;

  final GoLiveStreamKey key;
  final VoiceServerCredentials _credentials;
  final DiscordVoiceSocketFactory _socketFactory;

  final StreamController<(String, DiscordRtpFrame)> _video =
      StreamController.broadcast();
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  DiscordVoiceClient? _client;
  StreamSubscription<VoiceSignalingEvent>? _clientEvents;
  StreamSubscription<(String, DiscordRtpFrame)>? _videoPackets;
  int? _ssrc;
  bool _closed = false;

  /// Pictures arriving on this connection, tagged with whose SSRC carried them.
  Stream<(String, DiscordRtpFrame)> get video => _video.stream;

  /// What the connection is doing, in the same vocabulary voice uses.
  Stream<VoiceSignalingEvent> get events => _events.stream;

  /// The SSRC Discord assigned, once the connection is ready.
  int? get ssrc => _ssrc;

  Future<void> connect() async {
    if (_closed || _client != null) return;
    _diagnose('dialling');
    final client = _socketFactory.streamSocket(
      credentials: _credentials,
      streamKey: key,
    );
    _client = client;
    _clientEvents = client.events.listen(_onEvent);
    _videoPackets = client.videoPackets.listen(
      _video.add,
      onError: _video.addError,
    );
    await client.connect();
  }

  /// Sends one encrypted video frame, answering how many bytes went out.
  ///
  /// Throws when the connection is not up: a caller that sends before the
  /// endpoint answered would be encrypting against a cipher that does not
  /// exist yet, and silently dropping the frame would look like a stream that
  /// opened and showed nothing.
  int sendVideoFrame(DiscordRtpFrame frame) {
    final client = _client;
    if (client == null) {
      throw StateError('Discord stream transport is not ready');
    }
    return client.sendVideoFrame(frame);
  }

  /// Declares the video SSRCs on this connection.
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    final client = _client;
    if (client == null) return false;
    return client.announceVideo(enabled: enabled, settings: settings);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _videoPackets?.cancel();
    await _clientEvents?.cancel();
    await _client?.close();
    _client = null;
    await _video.close();
    await _events.close();
  }

  void _onEvent(VoiceSignalingEvent event) {
    if (event is VoiceTransportReadyEvent) {
      _ssrc = event.session.ssrc;
      _diagnose('ready', 'ssrc ${event.session.ssrc}');
    }
    if (event is VoiceSignalingStatusEvent) {
      _diagnose(event.status.name, event.error);
    }
    if (!_events.isClosed) _events.add(event);
  }

  /// Says what this connection is doing, apart from the call's.
  ///
  /// The two look identical in a log otherwise — same client, same statuses —
  /// and a stream that never opens is indistinguishable from a call that
  /// reconnected. No token, and no endpoint host: this is a diagnostic, not a
  /// record of where somebody's stream lives.
  void _diagnose(String what, [Object? detail]) {
    AppLog.warning(
      'stream',
      '[${key.userId}] $what${detail == null ? '' : ': $detail'}',
    );
  }
}
