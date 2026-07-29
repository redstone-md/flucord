import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_rtp_packet.dart';
import 'discord_voice_dave_controller.dart';
import 'discord_video_stream_transport.dart';
import 'discord_voice_gateway_protocol.dart';
import 'discord_voice_media_transport.dart';
import 'discord_voice_transport_cipher.dart';
import 'discord_voice_udp_transport.dart';
import 'discord_voice_websocket.dart';

abstract interface class DiscordVoiceClient {
  Stream<VoiceSignalingEvent> get events;

  Future<void> connect();
  Future<void> close();
}

final class DiscordVoiceGatewayClient
    implements DiscordVoiceClient, VoiceAudioTransport, VoiceVideoTransport {
  DiscordVoiceGatewayClient({
    required VoiceServerCredentials credentials,
    required int maxDaveProtocolVersion,
    VoiceDaveService? daveService,
    DiscordVoiceSocketConnector? socketConnector,
    DiscordVoiceUdpTransport? udpTransport,
  }) : _protocol = DiscordVoiceGatewayProtocol(
         credentials: credentials,
         maxDaveProtocolVersion: maxDaveProtocolVersion,
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
  Timer? _reconnectTimer;
  bool _heartbeatAcknowledged = true;
  bool _canResume = false;
  bool _closing = false;
  bool _failed = false;
  int _generation = 0;
  int? _ssrc;
  final Map<int, String> _userIdsBySsrc = {};
  /// Video SSRC to whoever announced it, from opcode 12.
  final Map<int, String> _videoSsrcOwners = {};
  String? _mode;
  DiscordVoiceIpDiscovery? _discovered;
  VoiceTransportSession? _session;
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

  /// The audio plane: everything that is not a camera.
  ///
  /// Split by payload type rather than by SSRC because the split has to work
  /// before anybody has announced anything — a video packet fed to the Opus
  /// decoder is noise, and one arriving before its opcode 12 would otherwise
  /// be exactly that.
  Stream<DiscordRtpFrame> get audioPackets => _decryptedPackets.where(
    (frame) => frame.header.payloadType != DiscordVideoStreamTransport.videoPayloadType,
  );

  /// Somebody else's camera, paired with whoever is sending it.
  ///
  /// A packet whose SSRC nobody has claimed is dropped: it belongs to a peer
  /// whose opcode 12 has not arrived, and guessing the owner would draw one
  /// person's face over another's tile.
  Stream<(String, DiscordRtpFrame)> get videoPackets => _decryptedPackets
      .where(
        (frame) =>
            frame.header.payloadType ==
            DiscordVideoStreamTransport.videoPayloadType,
      )
      .map((frame) => (_videoSsrcOwners[frame.header.ssrc], frame))
      .where((pair) => pair.$1 != null)
      .map((pair) => (pair.$1!, pair.$2));
  VoiceTransportSession? get session => _session;
  String? userIdForSsrc(int ssrc) => _userIdsBySsrc[ssrc];

  /// Who sends on a video SSRC, once their opcode 12 has said so.
  String? userIdForVideoSsrc(int ssrc) => _videoSsrcOwners[ssrc];
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
      _canResume
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
      _send(_canResume ? _protocol.resume() : _protocol.identify());
    } catch (error) {
      _scheduleReconnect(error: error);
    }
  }

  Uri _voiceUri() {
    final endpoint = _protocol.credentials.endpoint.trim();
    final base = Uri.parse(
      endpoint.contains('://') ? endpoint : 'wss://$endpoint',
    );
    return base.replace(
      scheme: 'wss',
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
    _protocol.acceptSequence(payload['seq']);
    final data = payload['d'];
    final opcode = payload['op'];
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
    switch (opcode) {
      case 2:
        if (data is Map) {
          unawaited(_handleReady(data.cast<String, Object?>(), generation));
        }
      case 4:
        if (data is Map) _handleSession(data.cast<String, Object?>());
      case 5:
        if (data is Map) _handleSpeaking(data.cast<String, Object?>());
      case 6:
        _heartbeatAcknowledged = true;
      case 8:
        if (data is Map) _handleHello(data.cast<String, Object?>());
      case 9:
        _canResume = true;
        _emitStatus(VoiceConnectionStatus.ready);
      case 12:
        if (data is Map) _handleClientVideo(data.cast<String, Object?>());
      case 13:
        if (data is Map) _handleClientDisconnect(data.cast<String, Object?>());
    }
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

  void _handleHello(Map<String, Object?> data) {
    final rawInterval = data['heartbeat_interval'];
    if (rawInterval is! num || rawInterval <= 0) return;
    _heartbeatTimer?.cancel();
    _heartbeatAcknowledged = true;
    final interval = Duration(milliseconds: rawInterval.round());
    _heartbeatTimer = Timer.periodic(interval, (_) => _heartbeat());
  }

  void _handleSpeaking(Map<String, Object?> data) {
    final userId = data['user_id'];
    final ssrc = data['ssrc'];
    final speakingFlags = data['speaking'];
    if (userId is! String ||
        ssrc is! int ||
        ssrc < 0 ||
        ssrc > 0xffffffff ||
        speakingFlags is! int) {
      return;
    }
    _userIdsBySsrc[ssrc] = userId;
    if (!_events.isClosed) {
      _events.add(
        VoiceSpeakingEvent(
          userId: userId,
          ssrc: ssrc,
          speakingFlags: speakingFlags,
        ),
      );
    }
  }

  /// Opcode 12 announces a peer's media layout, not their departure.
  ///
  /// It arrives when someone joins or changes their video state and carries the
  /// SSRCs they will send on. Taking `audio_ssrc` from here means a peer is
  /// resolvable before they ever speak, where opcode 5 only reveals them at
  /// their first speaking flag.
  void _handleClientVideo(Map<String, Object?> data) {
    final userId = data['user_id'];
    final audioSsrc = data['audio_ssrc'];
    if (userId is! String || audioSsrc is! int || audioSsrc == 0) return;
    _userIdsBySsrc[audioSsrc] = userId;
    // Taken from the frame rather than derived: the peer says which SSRC its
    // pictures will arrive on, and a client that assumed audio + 1 would
    // mis-attribute anybody whose layout differs.
    final videoSsrc = data['video_ssrc'];
    if (videoSsrc is int && videoSsrc != 0) {
      _videoSsrcOwners[videoSsrc] = userId;
    }
  }

  void _handleClientDisconnect(Map<String, Object?> data) {
    final userId = data['user_id'];
    if (userId is! String) return;
    _userIdsBySsrc.removeWhere((_, mappedUserId) => mappedUserId == userId);
    _videoSsrcOwners.removeWhere((_, mappedUserId) => mappedUserId == userId);
    if (!_events.isClosed) _events.add(VoiceUserDisconnectedEvent(userId));
  }

  void _heartbeat() {
    if (!_heartbeatAcknowledged) {
      _scheduleReconnect(error: StateError('Voice heartbeat not acknowledged'));
      return;
    }
    _heartbeatAcknowledged = false;
    _send(_protocol.heartbeat(DateTime.now().millisecondsSinceEpoch));
  }

  Future<void> _handleReady(Map<String, Object?> data, int generation) async {
    final ready = DiscordVoiceReady.tryParse(data);
    if (ready == null) {
      _fail(const FormatException('Invalid Discord voice Ready payload'));
      return;
    }
    final mode = _protocol.selectMode(ready.modes);
    if (mode == null) {
      _fail(StateError('Discord voice server offered no supported AEAD mode'));
      return;
    }
    _ssrc = ready.ssrc;
    _mode = mode;
    _discovered = null;
    _emitStatus(VoiceConnectionStatus.discovering);
    try {
      _daveController?.assignAudioSsrc(ready.ssrc);
      final discovered = await _udpTransport.discover(
        host: ready.ip,
        port: ready.port,
        ssrc: ready.ssrc,
      );
      if (_closing || _failed || generation != _generation) return;
      _discovered = discovered;
      _emitStatus(VoiceConnectionStatus.negotiating);
      _send(
        _protocol.selectProtocol(
          address: discovered.address,
          port: discovered.port,
          mode: mode,
        ),
      );
    } catch (error) {
      _fail(error);
    }
  }

  void _handleSession(Map<String, Object?> data) {
    final description = DiscordVoiceSessionDescription.tryParse(data);
    final ssrc = _ssrc;
    final mode = _mode;
    final discovered = _discovered;
    if (description == null ||
        ssrc == null ||
        mode == null ||
        discovered == null) {
      _fail(const FormatException('Invalid Discord voice session description'));
      return;
    }
    if (description.mode != mode ||
        description.daveProtocolVersion > _protocol.maxDaveProtocolVersion) {
      _fail(StateError('Discord selected an unsupported voice protocol'));
      return;
    }
    try {
      _daveController?.activate(description.daveProtocolVersion);
      _replaceTransportCipher(
        DiscordVoiceTransportCipher(
          mode: mode,
          secretKey: description.secretKey,
        ),
      );
    } catch (error) {
      _fail(error);
      return;
    }
    _session = VoiceTransportSession(
      guildId: _protocol.credentials.guildId,
      ssrc: ssrc,
      address: discovered.address,
      port: discovered.port,
      mode: mode,
      secretKey: description.secretKey,
      daveProtocolVersion: description.daveProtocolVersion,
    );
    _mediaTransport.configure(
      ssrc: ssrc,
      daveEnabled: description.daveProtocolVersion > 0,
    );
    _canResume = true;
    _emitStatus(VoiceConnectionStatus.ready);
    if (!_events.isClosed) _events.add(VoiceTransportReadyEvent(_session!));
  }

  void setSpeaking(bool enabled) {
    final ssrc = _ssrc;
    if (ssrc != null) _send(_protocol.speaking(ssrc: ssrc, enabled: enabled));
  }

  /// The SSRC Discord handed this session, or null before the voice `READY`.
  ///
  /// A camera sends on the one above it, which is how the desktop client
  /// derives its own video SSRC rather than being told one.
  @override
  int? get audioSsrc => _ssrc;

  /// Declares the camera's SSRCs with opcode 12, or marks them inactive.
  ///
  /// Answers whether the frame went out: before the voice `READY` there is no
  /// audio SSRC to derive the video one from, and announcing a camera the
  /// server has allocated nothing for would send pictures nobody forwards.
  @override
  bool announceVideo({
    required bool enabled,
    int width = 1280,
    int height = 720,
    int framesPerSecond = 30,
    int maxBitrate = 1200000,
  }) {
    final ssrc = _ssrc;
    if (ssrc == null) return false;
    _send(
      _protocol.video(
        audioSsrc: ssrc,
        enabled: enabled,
        width: width,
        height: height,
        framesPerSecond: framesPerSecond,
        maxBitrate: maxBitrate,
      ),
    );
    return true;
  }

  int sendAudioFrame(DiscordRtpFrame frame) {
    final cipher = _transportCipher;
    if (cipher == null) throw StateError('Voice transport is not ready');
    return _udpTransport.send(cipher.encryptFrame(frame));
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
        if (!_events.isClosed) {
          _events.add(
            VoiceSignalingStatusEvent(
              VoiceConnectionStatus.failure,
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
    if ({4004, 4006, 4009, 4011, 4014, 4017, 4020, 4021, 4022}.contains(code)) {
      _fail(StateError('Discord voice connection closed with code $code'));
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect({Object? error}) {
    if (_closing || _failed || _reconnectTimer?.isActive == true) return;
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _discovered = null;
    _session = null;
    _mediaTransport.reset();
    _replaceTransportCipher(null);
    _userIdsBySsrc.clear();
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.close());
    _emitStatus(VoiceConnectionStatus.reconnecting, error: error);
    _reconnectTimer = Timer(const Duration(seconds: 2), _open);
  }

  void _fail(Object error) {
    if (_closing || _failed) return;
    _failed = true;
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.close());
    _discovered = null;
    _session = null;
    _mediaTransport.reset();
    _replaceTransportCipher(null);
    _userIdsBySsrc.clear();
    _daveController?.dispose();
    _emitStatus(VoiceConnectionStatus.failure, error: error);
  }

  void _send(Map<String, Object?> payload) {
    _socket?.send(jsonEncode(payload));
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
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();
    await _socket?.close();
    await _udpTransport.close();
    _mediaTransport.reset();
    _replaceTransportCipher(null);
    _userIdsBySsrc.clear();
    _daveController?.dispose();
    _emitStatus(VoiceConnectionStatus.disconnected);
    await _events.close();
  }
}
