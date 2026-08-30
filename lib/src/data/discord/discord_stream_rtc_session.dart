import 'dart:async';
import 'dart:typed_data';


import '../../domain/go_live_stream.dart';
import '../../domain/voice_audio.dart';
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

    /// Whether this is the connection this account sends its share on, rather
    /// than one it watches a stream on.
    ///
    /// One key carries two connections while this account previews itself: the
    /// one the pictures go out on and the one they come back in on. Discord
    /// answers a create and a watch with the same endpoint shape, so nothing
    /// about the key tells them apart (ADR-0001).
    this.sending = false,
  }) : _credentials = credentials,
       _socketFactory = socketFactory;

  final GoLiveStreamKey key;
  final VoiceServerCredentials _credentials;
  final DiscordVoiceSocketFactory _socketFactory;

  /// Whether this account's share is sent on this connection.
  final bool sending;

  final StreamController<(String, DiscordRtpFrame)> _video =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _audio =
      StreamController.broadcast();
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  DiscordVoiceClient? _client;
  StreamSubscription<VoiceSignalingEvent>? _clientEvents;
  StreamSubscription<(String, DiscordRtpFrame)>? _videoPackets;
  StreamSubscription<VoiceRemoteOpusFrame>? _audioFrames;
  int? _ssrc;
  bool _closed = false;

  /// Pictures arriving on this connection, tagged with whose SSRC carried them.
  Stream<(String, DiscordRtpFrame)> get video => _video.stream;

  /// Audio arriving with the stream connection (ADR-0004).
  Stream<VoiceRemoteOpusFrame> get audio => _audio.stream;

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
    _audioFrames = client.remoteAudio.listen(
      _audio.add,
      onError: _audio.addError,
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

  /// Encrypts one whole picture for this stream's group, before the caller
  /// packetises it.
  Uint8List encryptVideoGroupFrame({
    required int ssrc,
    required Uint8List frame,
  }) {
    final client = _client;
    if (client == null) {
      throw StateError('Discord stream transport is not ready');
    }
    return client.encryptVideoForGroup(ssrc: ssrc, frame: frame);
  }

  /// Decrypts one whole picture for this stream's group, after the caller has
  /// put its packets back together.
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  }) {
    final client = _client;
    if (client == null) {
      throw StateError('Discord stream transport is not ready');
    }
    return client.decryptVideoGroupFrame(userId: userId, picture: picture);
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
    await _audioFrames?.cancel();
    await _clientEvents?.cancel();
    await _client?.close();
    _client = null;
    await _video.close();
    await _audio.close();
    await _events.close();
  }

  void _onEvent(VoiceSignalingEvent event) {
    if (event is VoiceTransportReadyEvent) {
      _ssrc = event.session.ssrc;
      _diagnose(
        'ready',
        'ssrc ${event.session.ssrc} '
        'dave ${event.session.daveProtocolVersion}',
      );
      // The SFU forwards no video until a receiver asks for it, so this goes
      // out before any picture is expected on the connection.
      if (!sending) {
        _client?.sendMediaSinkWants(any: 100);
      }
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
