import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_rtp_packet.dart';
import 'discord_voice_dave_controller.dart';
import 'discord_voice_gateway_protocol.dart';
import 'discord_voice_media_transport.dart';
import '../../domain/video_encoder.dart';
import 'discord_voice_transport_cipher.dart';
import 'discord_voice_udp_transport.dart';
import 'discord_voice_websocket.dart';

/// A connection on Discord's voice plane.
///
/// A call's socket and a Go Live stream's socket are the same thing
/// underneath: the same handshake, the same UDP media path, and pictures as
/// well as sound can cross either. The interface states the whole video half
/// so no caller needs the concrete class, and a test fake can carry pictures
/// through the same doors as the production client.
abstract interface class DiscordVoiceClient implements VoiceVideoTransport {
  Stream<VoiceSignalingEvent> get events;

  Future<void> connect();
  Future<void> close();

  /// Somebody else's pictures on this connection, tagged with whoever's SSRC
  /// carried them.
  Stream<(String, DiscordRtpFrame)> get videoPackets;

  /// Sends one picture, encrypted for the group first when the connection has
  /// a group to encrypt for.
  int sendVideoFrame(DiscordRtpFrame frame);
}

/// The socket driver for a voice gateway connection.
///
/// Every stateful Discord rule lives in [DiscordVoiceGatewayProtocol]: it
/// decides what a frame, a due heartbeat or a close code means, and this
/// class carries the decision out against the socket, the timers and the
/// media plane.
final class DiscordVoiceGatewayClient
    implements DiscordVoiceClient, VoiceAudioTransport {
  DiscordVoiceGatewayClient({
    required VoiceServerCredentials credentials,
    required int maxDaveProtocolVersion,
    VoiceDaveService? daveService,
    DiscordVoiceSocketConnector? socketConnector,
    DiscordVoiceUdpTransport? udpTransport,
    bool carriesVideo = false,
    String? streamKey,
  }) : _protocol = DiscordVoiceGatewayProtocol(
         credentials: credentials,
         maxDaveProtocolVersion: maxDaveProtocolVersion,
         carriesVideo: carriesVideo,
         streamKey: streamKey,
       ),
       _daveController = daveService == null
           ? null
           : DiscordVoiceDaveController(
               daveService: daveService,
               channelId: credentials.channelId,
               selfUserId: credentials.userId,
             ),
       _socketConnector =
           socketConnector ?? const IoDiscordVoiceSocketConnector(),
       _udpTransport = udpTransport ?? IoDiscordVoiceUdpTransport() {
    _mediaTransport = DiscordVoiceMediaTransport(
      incomingFrames: audioPackets,
      encryptDave: encryptDaveAudioFrame,
      decryptDave: (userId, frame) =>
          decryptDaveAudioFrame(userId: userId, encryptedFrame: frame),
      sendFrame: sendAudioFrame,
      sendSpeaking: setSpeaking,
      userForSsrc: userIdForSsrc,
    );
  }

  final DiscordVoiceGatewayProtocol _protocol;
  final DiscordVoiceDaveController? _daveController;
  final DiscordVoiceSocketConnector _socketConnector;
  final DiscordVoiceUdpTransport _udpTransport;
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  late final DiscordVoiceMediaTransport _mediaTransport;

  DiscordVoiceWebSocket? _socket;
  StreamSubscription<Object?>? _socketSubscription;
  Timer? _heartbeatTimer;
  Timer? _keepaliveTimer;
  int _keepaliveCounter = 0;
  Timer? _reconnectTimer;
  bool _closing = false;
  bool _failed = false;
  int _generation = 0;
  DiscordVoiceTransportCipher? _transportCipher;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  /// Every packet the socket produced, decrypted once.
  ///
  /// One subscription behind both planes: decrypting per listener would do the
  /// work twice and, with a nonce-carrying cipher, twice is not merely
  /// wasteful.
  late final Stream<DiscordRtpFrame> _decryptedPackets = _udpTransport.packets
      .expand(_decryptOrDrop)
      .asBroadcastStream();

  /// How many packets in a row failed to authenticate, and whether any ever
  /// have. Together they tell a stray packet apart from the wrong key.
  int _consecutiveAuthFailures = 0;
  bool _hasDecryptedAnyPacket = false;

  /// The audio plane: Opus, and only Opus.
  ///
  /// Named rather than "everything that is not our own video payload type",
  /// which is what this used to say. Discord's own clients send pictures on
  /// several payload types, and every one of them that was not ours landed in
  /// here — to be handed to the group decryptor as audio, fail, and put "DAVE
  /// decryption failed" over a call that was working.
  Stream<DiscordRtpFrame> get audioPackets => _decryptedPackets.where(
    (frame) =>
        frame.header.payloadType == DiscordRtpHeader.discordAudioPayloadType,
  );

  /// Somebody else's camera, paired with whoever is sending it.
  ///
  /// A packet whose SSRC nobody has claimed is dropped: it belongs to a peer
  /// whose opcode 12 has not arrived, and guessing the owner would draw one
  /// person's face over another's tile.
  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets => _decryptedPackets
      .where(
        (frame) =>
            frame.header.payloadType !=
            DiscordRtpHeader.discordAudioPayloadType,
      )
      .map((frame) => (_protocol.userIdForVideoSsrc(frame.header.ssrc), frame))
      .where((pair) => pair.$1 != null)
      // Through the group's decryptor as well, on a call that has one: the
      // transport cipher gets the packet off the wire, and what is inside it
      // is still encrypted for the room. A picture handed to the decoder in
      // that state decodes to nothing.
      .expand((pair) => _decryptVideoOrDrop(pair.$1!, pair.$2));
  VoiceTransportSession? get session => _protocol.session;
  String? userIdForSsrc(int ssrc) => _protocol.userIdForSsrc(ssrc);

  /// Who sends on a video SSRC, once their opcode 12 has said so.
  String? userIdForVideoSsrc(int ssrc) => _protocol.userIdForVideoSsrc(ssrc);
  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _mediaTransport.remoteAudio;

  @override
  Future<void> connect() async {
    _closing = false;
    _failed = false;
    await _open();
  }

  Future<void> _open() async {
    if (_closing || _failed) return;
    _emitStatus(
      _protocol.canResume
          ? VoiceConnectionStatus.reconnecting
          : VoiceConnectionStatus.connecting,
    );
    final generation = ++_generation;
    try {
      final socket = await _socketConnector.connect(_voiceUri());
      if (_closing || generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      _socketSubscription = socket.messages.listen(
        (message) => _onMessage(message, generation),
        onDone: () => _onDone(socket, generation),
        onError: (Object error) => _onSocketError(error, generation),
        cancelOnError: true,
      );
      _send(_protocol.canResume ? _protocol.resume() : _protocol.identify());
    } catch (error) {
      _scheduleReconnect(error: error);
    }
  }

  Uri _voiceUri() {
    // The port Discord names is the UDP one — the media path — and dialling
    // the websocket on it is answered with 4017 once the handshake finishes.
    // The socket belongs on 443, which is what dropping the port leaves.
    final endpoint = _protocol.credentials.endpoint.trim().split(':').first;
    final base = Uri.parse(
      endpoint.contains('://') ? endpoint : 'wss://$endpoint',
    );
    // Explicitly 443: a URI parsed from a bare host has no port at all, and
    // `replace` keeps that — which dialled port 0 and was answered with a 522.
    return base.replace(
      scheme: 'wss',
      port: base.hasPort && base.port != 0 ? base.port : 443,
      queryParameters: {...base.queryParameters, 'v': '8'},
    );
  }

  void _onMessage(Object? raw, int generation) {
    if (_closing || _failed || generation != _generation) return;
    if (raw is List<int>) {
      _handleBinary(Uint8List.fromList(raw));
      return;
    }
    if (raw is! String) return;
    final Map<String, Object?> payload;
    try {
      payload = (jsonDecode(raw) as Map).cast<String, Object?>();
    } on FormatException {
      return;
    } on TypeError {
      return;
    }
    final data = payload['d'];
    final opcode = payload['op'];
    // Only for a stream socket, and only the opcode: this is the handshake
    // that keeps being refused, and knowing how far it got — hello, ready,
    // nothing at all — is the difference between reading and guessing.
    if (_protocol.carriesVideo) _diagnose('received op $opcode');
    if (opcode is int && data is Map) {
      try {
        _executeDaveCommands(
          _daveController?.acceptJson(opcode, data.cast<String, Object?>()) ??
              const [],
        );
      } catch (error) {
        _fail(error);
        return;
      }
    }
    for (final action in _protocol.accept(payload)) {
      _apply(action);
    }
  }

  /// Carries a protocol decision out against the socket, the timers and the
  /// media plane.
  void _apply(DiscordVoiceGatewayAction action) {
    switch (action) {
      case DiscordVoiceGatewaySend(:final payload):
        _send(payload);
      case DiscordVoiceGatewayScheduleHeartbeat(:final interval):
        _startHeartbeat(interval);
      case DiscordVoiceGatewayReconnect(:final error):
        _scheduleReconnect(error: error);
      case DiscordVoiceGatewayAwaitCredentials(:final error):
        // The token is dead; the main gateway will hand over a fresh
        // VOICE_SERVER_UPDATE and the connection is rebuilt from that.
        _emitStatus(VoiceConnectionStatus.reconnecting, error: error);
      case DiscordVoiceGatewayFail(:final error):
        _fail(error);
      case DiscordVoiceGatewayDispatch(:final event):
        if (!_events.isClosed) _events.add(event);
      case DiscordVoiceGatewayDiscoverUdp():
        unawaited(_discoverUdp(action));
      case DiscordVoiceGatewayTransportReady(:final session):
        _activateTransport(session);
    }
  }

  void _startHeartbeat(Duration interval) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) => _heartbeat());
  }

  void _heartbeat() => _apply(_protocol.heartbeatDue());

  /// The one handshake step that needs real I/O: punch the UDP hole, then
  /// let the protocol announce the address it produced.
  Future<void> _discoverUdp(DiscordVoiceGatewayDiscoverUdp action) async {
    final generation = _generation;
    _emitStatus(VoiceConnectionStatus.discovering);
    try {
      _daveController?.assignAudioSsrc(action.ready.ssrc);
      final discovered = await _udpTransport.discover(
        host: action.ready.ip,
        port: action.ready.port,
        ssrc: action.ready.ssrc,
      );
      if (_closing || _failed || generation != _generation) return;
      _emitStatus(VoiceConnectionStatus.negotiating);
      for (final next in _protocol.udpDiscovered(discovered)) {
        _apply(next);
      }
    } on Object catch (error) {
      _fail(error);
    }
  }

  /// Builds the media plane for a negotiated session: the cipher, the DAVE
  /// controller's version, and the keepalive that keeps the UDP path open.
  void _activateTransport(VoiceTransportSession session) {
    try {
      _daveController?.activate(session.daveProtocolVersion);
      _replaceTransportCipher(
        DiscordVoiceTransportCipher(
          mode: session.mode,
          secretKey: session.secretKey,
        ),
      );
    } on Object catch (error) {
      _fail(error);
      return;
    }
    _mediaTransport.configure(
      ssrc: session.ssrc,
      daveEnabled: session.daveProtocolVersion > 0,
    );
    _startUdpKeepalive();
    _emitStatus(VoiceConnectionStatus.ready);
    if (!_events.isClosed) _events.add(VoiceTransportReadyEvent(session));
  }

  void _handleBinary(Uint8List message) {
    if (message.length < 3) return;
    final sequence = ByteData.sublistView(message).getUint16(0, Endian.big);
    _protocol.acceptSequence(sequence);
    if (!_events.isClosed) {
      _events.add(
        VoiceDaveBinaryEvent(
          opcode: message[2],
          payload: message.sublist(3),
          sequence: sequence,
        ),
      );
    }
    try {
      _executeDaveCommands(
        _daveController?.acceptBinary(
              opcode: message[2],
              payload: message.sublist(3),
            ) ??
            const [],
      );
    } catch (error) {
      _fail(error);
    }
  }

  /// Keeps the UDP path open while nothing is being said.
  ///
  /// The voice socket's heartbeat proves the *websocket* is alive; it says
  /// nothing about the UDP path the audio actually takes. A muted client sends
  /// no RTP at all, so the NAT mapping that path depends on expires, Discord
  /// stops hearing from the address it was told to send to, and the session is
  /// closed with 4014 — which is what had a quiet call reconnecting every
  /// minute or so. Discord's own libraries send a counter on the same socket
  /// for exactly this.
  void _startUdpKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sendKeepalive(),
    );
  }

  void _sendKeepalive() {
    if (_closing || _failed || _protocol.session == null) return;
    final packet = Uint8List(8);
    ByteData.sublistView(packet).setUint32(0, _keepaliveCounter, Endian.little);
    _keepaliveCounter = (_keepaliveCounter + 1) & 0xffffffff;
    try {
      _udpTransport.send(packet);
    } on Object catch (error) {
      // A keepalive that cannot go out is a dead socket, and the socket's own
      // failure path is the one that should report it.
      _diagnose('keepalive failed', error);
    }
  }

  void setSpeaking(bool enabled) {
    final ssrc = _protocol.audioSsrc;
    if (ssrc != null) _send(_protocol.speaking(ssrc: ssrc, enabled: enabled));
  }

  /// The SSRC Discord handed this session, or null before the voice `READY`.
  ///
  /// A camera sends on the one above it, which is how the desktop client
  /// derives its own video SSRC rather than being told one.
  @override
  int? get audioSsrc => _protocol.audioSsrc;

  /// Declares the camera's SSRCs with opcode 12, or marks them inactive.
  ///
  /// Answers whether the frame went out: before the voice `READY` there is no
  /// audio SSRC to derive the video one from, and announcing a camera the
  /// server has allocated nothing for would send pictures nobody forwards.
  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    final ssrc = _protocol.audioSsrc;
    if (ssrc == null) return false;
    _send(
      _protocol.video(audioSsrc: ssrc, enabled: enabled, settings: settings),
    );
    return true;
  }

  int sendAudioFrame(DiscordRtpFrame frame) {
    final cipher = _transportCipher;
    if (cipher == null) throw StateError('Voice transport is not ready');
    return _udpTransport.send(cipher.encryptFrame(frame));
  }

  /// Sends one picture, encrypted for the group first when the call has a
  /// group to encrypt for.
  ///
  /// The transport cipher alone is not enough on a DAVE call: every receiver
  /// runs the payload through the group's decryptor, and one that was sent in
  /// the clear comes back as `decryptionFailure` — a share that arrives and
  /// draws nothing.
  @override
  int sendVideoFrame(DiscordRtpFrame frame) {
    final controller = _daveController;
    final ssrc = frame.header.ssrc;
    if (controller == null) return sendAudioFrame(frame);
    return sendAudioFrame(
      DiscordRtpFrame(
        header: frame.header,
        payload: controller.encryptVideoFrame(ssrc: ssrc, frame: frame.payload),
      ),
    );
  }

  @override
  void sendOpusFrame(Uint8List opusFrame) =>
      _mediaTransport.sendOpusFrame(opusFrame);

  @override
  Future<void> finishSpeaking() => _mediaTransport.finishSpeaking();

  /// One packet, or nothing at all.
  ///
  /// A packet that will not authenticate is dropped rather than thrown. That
  /// is what RTP implementations do, and it has to be: the same port carries
  /// RTCP, packets that arrive after a key rotation, and anything else the
  /// network delivers, and none of those should end a call. Letting one
  /// through as an exception took the whole voice stream down.
  ///
  /// Silence is not the answer either. If nothing has ever decrypted, the key
  /// or the mode is wrong rather than the packet, and the room is told after
  /// enough attempts to be sure.
  Iterable<DiscordRtpFrame> _decryptOrDrop(Uint8List packet) {
    try {
      final frame = _decryptAudioPacket(packet);
      _hasDecryptedAnyPacket = true;
      _consecutiveAuthFailures = 0;
      return [frame];
    } on Object catch (error) {
      _consecutiveAuthFailures++;
      if (!_hasDecryptedAnyPacket &&
          _consecutiveAuthFailures == _authFailureLimit) {
        // A key that decrypts nothing at all is a key from a session that has
        // been replaced — the main gateway reconnected, Discord issued new
        // credentials, and this socket is still holding the old secret. That
        // is asked to be re-issued, not reported as a broken call: failing
        // here dropped somebody out of a channel Discord still had them in.
        _protocol.revokeResume();
        _diagnose('nothing decrypts, asking for a new session', error);
        if (!_events.isClosed) {
          _events.add(
            VoiceSignalingStatusEvent(
              VoiceConnectionStatus.reconnecting,
              error: StateError(
                'Voice packets from Discord could not be decrypted '
                '($_authFailureLimit in a row, none succeeded): $error',
              ),
            ),
          );
        }
      }
      return const [];
    }
  }

  /// One picture, decrypted for the group, or none when its key is missing.
  ///
  /// Dropped rather than raised: a frame arriving before the sender's key has
  /// been distributed is ordinary at the start of a share, and the next one
  /// usually decrypts.
  Iterable<(String, DiscordRtpFrame)> _decryptVideoOrDrop(
    String userId,
    DiscordRtpFrame frame,
  ) {
    final controller = _daveController;
    if (controller == null) return [(userId, frame)];
    try {
      return [
        (
          userId,
          DiscordRtpFrame(
            header: frame.header,
            payload: controller.decryptVideoFrame(
              userId: userId,
              encryptedFrame: frame.payload,
            ),
          ),
        ),
      ];
    } on Object {
      return const [];
    }
  }

  /// How many failures in a row are needed before the key is blamed rather
  /// than the packet. A handful of strays is ordinary; fifty is not.
  static const _authFailureLimit = 50;

  DiscordRtpFrame _decryptAudioPacket(Uint8List packet) {
    final cipher = _transportCipher;
    if (cipher == null) throw StateError('Voice transport is not ready');
    return cipher.decryptPacket(packet);
  }

  Uint8List encryptDaveAudioFrame(Uint8List opusFrame) {
    final controller = _daveController;
    if (controller == null) throw StateError('DAVE is unavailable');
    return Uint8List.fromList(controller.encryptAudioFrame(opusFrame));
  }

  Uint8List decryptDaveAudioFrame({
    required String userId,
    required Uint8List encryptedFrame,
  }) {
    final controller = _daveController;
    if (controller == null) throw StateError('DAVE is unavailable');
    return Uint8List.fromList(
      controller.decryptAudioFrame(
        userId: userId,
        encryptedFrame: encryptedFrame,
      ),
    );
  }

  void sendDaveMessage({required int opcode, required List<int> payload}) {
    _socket?.send(Uint8List.fromList([opcode, ...payload]));
  }

  void _executeDaveCommands(List<DiscordVoiceDaveCommand> commands) {
    for (final command in commands) {
      switch (command) {
        case DiscordVoiceDaveJsonCommand():
          _send({'op': command.opcode, 'd': command.data});
        case DiscordVoiceDaveBinaryCommand():
          sendDaveMessage(opcode: command.opcode, payload: command.payload);
      }
    }
  }

  void _onSocketError(Object error, int generation) {
    if (generation == _generation) _scheduleReconnect(error: error);
  }

  void _onDone(DiscordVoiceWebSocket socket, int generation) {
    if (_closing || _failed || generation != _generation) return;
    final code = socket.closeCode;
    _diagnose('socket closed', 'code $code');
    _apply(_protocol.closedWithCode(code));
  }

  /// Says what the transport just did, where it can actually be read.
  ///
  /// `dart:developer` alone goes to the VM service, which a desktop build's
  /// console never shows — and a reconnect nobody can see the reason for is
  /// the difference between a fix and a guess.
  static String _tail(Object? value) {
    final text = value is String ? value : '';
    return text.length <= 4 ? '?' : text.substring(text.length - 4);
  }

  void _diagnose(String what, [Object? detail]) {
    final line =
        'flucord.voice.transport $what'
        '${detail == null ? '' : ': $detail'}';
    developer.log(line, name: 'flucord.discord.voice', level: 900);
    if (kDebugMode) stdout.writeln(line);
  }

  void _scheduleReconnect({Object? error}) {
    if (_closing || _failed || _reconnectTimer?.isActive == true) return;
    _diagnose('reconnecting', error);
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _protocol.dropSession();
    _mediaTransport.reset();
    _replaceTransportCipher(null);
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.close());
    _emitStatus(VoiceConnectionStatus.reconnecting, error: error);
    _reconnectTimer = Timer(const Duration(seconds: 2), _open);
  }

  void _fail(Object error) {
    if (_closing || _failed) return;
    _diagnose('failed', error);
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _failed = true;
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.close());
    _protocol.dropSession();
    _mediaTransport.reset();
    _replaceTransportCipher(null);
    _daveController?.dispose();
    _emitStatus(VoiceConnectionStatus.failure, error: error);
  }

  /// Writes to the voice socket, or gives up on it.
  ///
  /// A socket can close between the last thing read from it and the next
  /// write, and the write then throws from wherever the caller happened to be
  /// — turning on a camera, in the crash this was found in, which took the
  /// whole client down. A dead socket is a reconnect, not an exception for the
  /// caller to have anticipated.
  void _send(Map<String, Object?> payload) {
    final socket = _socket;
    if (socket == null) return;
    // Identify is the one frame worth reading back: everything after it
    // depends on Discord having accepted it, and a rejection arrives as a
    // close code with nothing attached. The token is not in here.
    final identity = payload['op'] == 0 ? payload['d'] : null;
    if (identity is Map<String, Object?>) {
      final d = identity;
      _diagnose(
        'identify',
        'server=${d['server_id']} channel=${d['channel_id']} '
            'video=${d['video']} streams=${d['streams'] != null} '
            'dave=${d['max_dave_protocol_version']} '
            // The last few characters only: enough to tell two sessions
            // apart, not enough to be one.
            'session=…${_tail(d['session_id'])} '
            'token=…${_tail(d['token'])} user=${d['user_id']} '
            // The host, which is Discord's own address for the region — not
            // anything about who is on it.
            'host=${_protocol.credentials.endpoint}',
      );
    }
    try {
      socket.send(jsonEncode(payload));
    } on Object catch (error) {
      _diagnose('send failed', error);
      _scheduleReconnect(error: error);
    }
  }

  void _replaceTransportCipher(DiscordVoiceTransportCipher? cipher) {
    _transportCipher?.dispose();
    _transportCipher = cipher;
  }

  void _emitStatus(VoiceConnectionStatus status, {Object? error}) {
    if (!_events.isClosed) {
      _events.add(VoiceSignalingStatusEvent(status, error: error));
    }
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _failed = false;
    _generation++;
    _heartbeatTimer?.cancel();
    _keepaliveTimer?.cancel();
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();
    await _socket?.close();
    await _udpTransport.close();
    _protocol.dropSession();
    _mediaTransport.reset();
    _replaceTransportCipher(null);
    _daveController?.dispose();
    _emitStatus(VoiceConnectionStatus.disconnected);
    await _events.close();
  }
}
