import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_rtcp_packet.dart';
import 'discord_rtp_packet.dart';
import 'discord_rtp_reorder_buffer.dart';
import 'discord_voice_dave_controller.dart';
import 'discord_voice_gateway_protocol.dart';
import 'discord_voice_media_transport.dart';
import '../../domain/video_encoder.dart';
import 'discord_voice_transport_cipher.dart';
import 'discord_voice_udp_transport.dart';
import 'discord_voice_websocket.dart';
import '../../app_log.dart';

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

  /// Remote audio arriving on this connection (ADR-0004).
  Stream<VoiceRemoteOpusFrame> get remoteAudio;

  /// Encrypts one whole picture for the room's group, when the connection has
  /// one, before it is packetised into RTP.
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  });

  /// Sends one picture, already encrypted for the group when the connection
  /// has a group to encrypt for.
  int sendVideoFrame(DiscordRtpFrame frame);

  /// Decrypts one whole picture for the room's group, after the caller has
  /// reassembled it from its packets.
  ///
  /// The mirror of [encryptVideoForGroup], and the other half of the same
  /// rule: a sender encrypts a whole picture and packetises that, so only the
  /// reassembled picture is a ciphertext anybody can open.
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  });

  /// Subscribes to remote video. The media server forwards no picture until
  /// a receiver asks, so a stream without this sends sound and draws nothing.
  ///
  /// [Media Sink Wants]: https://discord.com/developers/docs/change-log#media-sink-wants
  void sendMediaSinkWants({
    Map<int, int> perSsrc = const {},
    int? any,
    Map<int, double> pixelCounts = const {},
  });

  /// Asks whoever sends [mediaSsrc] for a fresh keyframe (RFC 4585): the
  /// pictures a viewer holds references to are gone, and only a new keyframe
  /// starts the stream over from something whole.
  void sendPictureLoss({required int mediaSsrc});
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
               channelId: DiscordVoiceGatewayProtocol.daveGroupId(
                 credentials,
                 carriesVideo: carriesVideo,
               ),
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
  ///
  /// Still encrypted for the room, when the room has a group. The transport
  /// cipher gets these packets off the wire; the group's cipher is a second
  /// layer that covers a whole picture, so it is applied by whoever puts the
  /// packets back together and not here, where only one packet is in hand.
  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets => _decryptedPackets
      .where(
        (frame) =>
            frame.header.payloadType !=
            DiscordRtpHeader.discordAudioPayloadType,
      )
      .expand(_reorderVideo)
      .map(
        (frame) =>
            (_protocol.userIdForVideoSsrc(frame.header.ssrc), frame),
      )
      .where((pair) => pair.$1 != null)
      .map((pair) => (pair.$1!, pair.$2));

  /// Puts a sender's video packets back into RTP sequence order.
  ///
  /// A picture is one sender's fragments in one sequence, and UDP does not
  /// promise to keep the order: a keyframe arrives as a burst of a dozen
  /// fragments, and one swap scrambles bytes the group cipher will not open.
  /// Audio reorders inside the media transport; video does it here. In-order
  /// frames pass straight through, so nothing is added to their latency.
  Iterable<DiscordRtpFrame> _reorderVideo(DiscordRtpFrame frame) {
    if (frame.header.payloadType ==
        DiscordRtpHeader.discordVideoRtxPayloadType) {
      final restored = _restoreRetransmission(frame);
      if (restored == null) return const [];
      frame = restored;
      // TEMP DIAGNOSTICS (remove after the live picture check).
      if (_rtxRestored++ < 5) {
        _diagnose(
          'video retransmission restored: seq ${frame.header.sequence} '
          'ssrc ${frame.header.ssrc} len ${frame.payload.length}',
        );
      }
    }
    // TEMP DIAGNOSTICS (remove after the live picture check): the sender
    // rounds some packets up with RTP padding, which used to ride along and
    // break the group cipher's byte count.
    if (frame.header.padding && _paddedPackets++ < 5) {
      _diagnose(
        'video packet carried RTP padding: seq ${frame.header.sequence} '
        'len ${frame.payload.length}',
      );
    }
    final buffer = _videoReorder.putIfAbsent(
      frame.header.ssrc,
      // Wider than audio's: one dropped fragment costs a whole picture, and
      // holding a few packets longer costs nothing on an in-order stream.
      () => DiscordRtpReorderBuffer(maxReorderDistance: 8),
    );
    // A packet that jumped ahead of the expected one just exposed a hole.
    // Ask for it now, while the hole is still inside the buffer's window and
    // a retransmission can still be spliced in: asking only when the buffer
    // finally gives up on the gap is asking too late, because by then it has
    // moved its waiting point past the hole and a restored packet cannot be
    // accepted any more. That used to turn every small loss into a whole
    // lost picture, and every lost picture into a keyframe request.
    final expected = buffer.nextSequence;
    if (expected != null &&
        frame.header.payloadType !=
            DiscordRtpHeader.discordVideoRtxPayloadType) {
      final ahead = (frame.header.sequence - expected) & 0xffff;
      if (ahead > 0 && ahead < 0x8000) {
        final pending = _nackPending.putIfAbsent(frame.header.ssrc, () => {});
        for (var missing = expected;
            missing != frame.header.sequence;
            missing = (missing + 1) & 0xffff) {
          pending.putIfAbsent(missing, () => 0);
        }
        _ensureNackTimer();
      }
    }
    final ordered = buffer.add(frame);
    // TEMP DIAGNOSTICS (remove after the live picture check): they show how
    // often the network really swaps or loses video packets.
    if (ordered.isEmpty) {
      if (_reorderDrops++ < 5) {
        _diagnose(
          'video packet too late to order: '
          'seq ${frame.header.sequence} ssrc ${frame.header.ssrc}',
        );
      }
    } else {
      if (ordered.first.missingFramesBefore > 0 && _reorderGaps < 5) {
        _reorderGaps++;
        _diagnose(
          'video gap of ${ordered.first.missingFramesBefore} before '
          'seq ${ordered.first.frame.header.sequence}',
        );
      }
      _askForLostPackets(ordered.first);
    }
    // What arrived is no longer owed, even if a NACK for it is still in
    // flight.
    _nackPending[frame.header.ssrc]?.removeWhere(
      (sequence, _) => ordered.any(
        (entry) => entry.frame.header.sequence == sequence,
      ),
    );
    return [for (final entry in ordered) entry.frame];
  }

  /// Puts a retransmission back in the original packet's place.
  ///
  /// Retransmissions ride the video SSRC one above their original's (RFC
  /// 4588), with the original sequence number ahead of the original payload.
  DiscordRtpFrame? _restoreRetransmission(DiscordRtpFrame frame) {
    final payload = frame.payload;
    if (payload.length <= 2) return null;
    return DiscordRtpFrame(
      header: DiscordRtpHeader(
        sequence: (payload[0] << 8) | payload[1],
        timestamp: frame.header.timestamp,
        ssrc: (frame.header.ssrc - 1) & 0xffffffff,
        payloadType: DiscordRtpHeader.discordVideoPayloadType,
        marker: frame.header.marker,
      ),
      payload: payload.sublist(2),
    );
  }

  /// Asks the media server to send again what never arrived (RFC 4585): the
  /// hole before [first]'s sequence number, where the reorder buffer skipped
  /// over packets the network dropped.
  void _askForLostPackets(DiscordOrderedRtpFrame first) {
    if (first.missingFramesBefore <= 0) return;
    final ssrc = first.frame.header.ssrc;
    final sequence = first.frame.header.sequence;
    final pending = _nackPending.putIfAbsent(ssrc, () => {});
    for (var missing = (sequence - first.missingFramesBefore) & 0xffff;
        missing != sequence;
        missing = (missing + 1) & 0xffff) {
      pending.putIfAbsent(missing, () => 0);
    }
    _ensureNackTimer();
  }

  void _ensureNackTimer() {
    _nackTimer ??= Timer.periodic(
      // Faster than a human notices, slower than the wire needs to answer.
      const Duration(milliseconds: 40),
      (_) => _flushNacks(),
    );
  }

  /// Sends what is still owed, and gives up on sequences the server has not
  /// answered after a few asks: a packet lost that hard is lost.
  void _flushNacks() {
    final cipher = _transportCipher;
    final session = _protocol.session;
    if (cipher == null || session == null || _closing || _failed) return;
    var anythingPending = false;
    for (final ssrc in _nackPending.keys.toList()) {
      final pending = _nackPending[ssrc]!;
      if (pending.isEmpty) {
        _nackPending.remove(ssrc);
        continue;
      }
      anythingPending = true;
      // One increasing run: the pending window is small, so unwrapping it
      // around any one member puts it in order.
      final anchor = pending.keys.first;
      final ordered = pending.keys.toList()
        ..sort(
          (a, b) => ((a - anchor) & 0xffff).compareTo((b - anchor) & 0xffff),
        );
      final asked = ordered.take(32).toList();
      final packet = DiscordRtcpPacket.nack(
        senderSsrc: session.ssrc,
        mediaSsrc: ssrc,
        sequences: asked,
      );
      // TEMP DIAGNOSTICS (remove after the live picture check).
      if (_nacksSent++ < 5) {
        _diagnose('nack sent for ${asked.join(',')} (ssrc $ssrc)');
      }
      try {
        _udpTransport.send(cipher.encryptRtcp(packet));
      } on Object {
        // A feedback packet that cannot go out is a dead socket, and the
        // socket's own path says so when the real media fails too.
        return;
      }
      for (final sequence in asked) {
        final tries = pending[sequence]! + 1;
        if (tries >= 8) {
          pending.remove(sequence);
        } else {
          pending[sequence] = tries;
        }
      }
    }
    if (!anythingPending) {
      _nackTimer?.cancel();
      _nackTimer = null;
    }
  }

  final Map<int, DiscordRtpReorderBuffer> _videoReorder = {};
  final Map<int, Map<int, int>> _nackPending = {};
  Timer? _nackTimer;
  int _reorderDrops = 0;
  int _plisSent = 0;
  int _pliBlocked = 0;
  int _reorderGaps = 0;
  // TEMP DIAGNOSTICS (remove after the live picture check).
  int _paddedPackets = 0;
  int _rtxRestored = 0;
  int _nacksSent = 0;

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
    final endpoint = _protocol.credentials.endpoint.trim();
    final base = Uri.parse(
      endpoint.contains('://') ? endpoint : 'wss://$endpoint',
    );
    // The port the endpoint names is where the session lives. Dropping it in
    // favour of 443 reached a frontend that answered every identify with
    // `sessionInvalid` — five refusals over two days, each on an endpoint
    // naming a port other than 443, while the one endpoint naming 443 was the
    // one connection that ever opened. (The `identifyRefused` once blamed on
    // dialling the named port came from a stream identify that had not yet
    // learned to declare its screen.) 443 remains the default for an endpoint
    // that names no port at all: a URI parsed from a bare host has none, and
    // `replace` keeps that, which dialled port 0 and was answered with a 522.
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
        //
        // This socket is finished, not merely idle: a heartbeat timer left
        // running counts acknowledgements a closed socket can never deliver,
        // and its watchdog then redials this endpoint with the dead token,
        // exactly what waiting was meant to avoid.
        _generation++;
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        _keepaliveTimer?.cancel();
        _keepaliveTimer = null;
        unawaited(_socketSubscription?.cancel());
        _socketSubscription = null;
        unawaited(_socket?.close());
        _socket = null;
        _protocol.dropSession();
        _mediaTransport.reset();
        _replaceTransportCipher(null);
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
    var daveCommands = const <DiscordVoiceDaveCommand>[];
    try {
      daveCommands =
          _daveController?.activate(session.daveProtocolVersion) ??
          const <DiscordVoiceDaveCommand>[];
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
    _executeDaveCommands(daveCommands);
    _videoReorder.clear();
    _nackPending.clear();
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
  /// closed with `serverMoved`, which is what had a quiet call
  /// reconnecting every minute or so. Discord's own libraries send a
  /// counter on the same socket for exactly this.
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
    // Declaring the camera or share's SSRC and teaching the group encryptor
    // which codec it carries are the same fact, stated once.
    _daveController?.assignVideoSsrc(
      DiscordVoiceGatewayProtocol.videoSsrcFor(ssrc),
    );
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

  /// Sends one picture, already encrypted for the group when the connection
  /// has a group.
  ///
  /// Group encryption happens a frame at a time, before packetisation, in
  /// [encryptVideoForGroup]: receivers reassemble a picture and decrypt it
  /// once, so what crosses here is ciphertext with an RTP header built around
  /// it, and the transport cipher is the only encryption applied.
  @override
  int sendVideoFrame(DiscordRtpFrame frame) => sendAudioFrame(frame);

  @override
  void sendMediaSinkWants({
    Map<int, int> perSsrc = const {},
    int? any,
    Map<int, double> pixelCounts = const {},
  }) {
    _send(
      _protocol.mediaSinkWants(
        perSsrc: perSsrc,
        any: any,
        pixelCounts: pixelCounts,
      ),
    );
  }

  @override
  void sendPictureLoss({required int mediaSsrc}) {
    final cipher = _transportCipher;
    final session = _protocol.session;
    if (cipher == null || session == null) {
      if (_pliBlocked++ < 3) {
        _diagnose('picture loss blocked: cipher ${cipher != null}, '
            'session ${session != null}');
      }
      return;
    }
    // TEMP DIAGNOSTICS: proves the keyframe ask leaves at all. A sender that
    // never answers it leaves references broken and the picture smeared.
    if (_plisSent++ < 3 || _plisSent % 10 == 0) {
      _diagnose('picture loss indication sent for $mediaSsrc ($_plisSent)');
    }
    try {
      final feedback = [
        cipher.encryptRtcp(
          DiscordRtcpPacket.pictureLoss(
            senderSsrc: session.ssrc,
            mediaSsrc: mediaSsrc,
          ),
        ),
        cipher.encryptRtcp(
          DiscordRtcpPacket.fullIntraRequest(
            senderSsrc: session.ssrc,
            mediaSsrc: mediaSsrc,
            commandSequence: _plisSent,
          ),
        ),
      ];
      for (final packet in feedback) {
        _udpTransport.send(packet);
      }
    } on Object {
      // Feedback that cannot leave is a dead socket, and the media path
      // reports that when the real media fails too.
    }
  }

  /// Encrypts one whole access unit for the room's group, when there is one.
  ///
  /// A frame that comes back unchanged is passthrough: a connection without
  /// a group, or one whose key has not been distributed yet, carries the
  /// picture in the clear behind the transport cipher.
  @override
  Uint8List encryptVideoForGroup({required int ssrc, required Uint8List frame}) {
    final controller = _daveController;
    if (controller == null) return frame;
    return Uint8List.fromList(
      controller.encryptVideoFrame(ssrc: ssrc, frame: frame),
    );
  }

  @override
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  }) {
    final controller = _daveController;
    if (controller == null) return picture;
    return Uint8List.fromList(
      controller.decryptVideoFrame(userId: userId, encryptedFrame: picture),
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
    // The media port carries traffic that is not media and never could
    // authenticate: RTCP feedback for the pictures this client is sending
    // (its packet types, 192-223, are ones RTP never uses) and the
    // eight-byte keepalives. Dropping them before the attempt keeps them out
    // of the stale-key count, where a send-only stream socket collected
    // fifty in a row and asked for a new session the one it had was fine.
    if (_isNotEncryptedMedia(packet)) {
      _acceptFeedback(packet);
      return const [];
    }
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

  /// How many failures in a row are needed before the key is blamed rather
  /// than the packet. A handful of strays is ordinary; fifty is not.
  static const _authFailureLimit = 50;

  /// What the media port carries that is not encrypted media: smaller than a
  /// header, a tag and a nonce could ever be, or typed as RTCP.
  static bool _isNotEncryptedMedia(Uint8List packet) {
    if (packet.length <
        12 +
            DiscordVoiceTransportCipher.authenticationTagLength +
            DiscordVoiceTransportCipher.nonceSuffixLength) {
      return true;
    }
    final packetType = packet[1];
    return packetType >= 192 && packetType <= 223;
  }

  /// The RTCP the media server relays about the pictures this client sends:
  /// receiver reports, the packets a viewer did not get, and picture-loss
  /// indications. Each becomes an event for whoever is sending.
  ///
  /// An RTCP packet that will not decrypt still answers a picture-loss
  /// indication from its clear header, which is what this path did before
  /// it could read the rest; the count of them is logged once so a wrong
  /// envelope shows up rather than passing as a quiet network.
  void _acceptFeedback(Uint8List packet) {
    if (!DiscordRtcpPacket.isRtcp(packet)) return;
    final cipher = _transportCipher;
    List<DiscordRtcpReport> reports;
    try {
      if (cipher == null) throw StateError('no transport cipher yet');
      reports = DiscordRtcpPacket.parse(cipher.decryptRtcp(packet));
    } on Object catch (error) {
      if (_undecryptableFeedback++ == 0) {
        _diagnose('rtcp did not decrypt, reading headers only', error);
      }
      reports = (packet[0] & 0x1f) == 1 &&
              packet[1] == DiscordRtcpPacket.payloadFeedback
          ? const [DiscordRtcpPictureLoss(mediaSsrc: 0)]
          : const [];
    }
    if (_events.isClosed) return;
    for (final report in reports) {
      switch (report) {
        case DiscordRtcpPictureLoss():
          _requestKeyframe();
        case DiscordRtcpNack(:final mediaSsrc, :final sequences):
          _events.add(
            VoiceRetransmitRequestedEvent(ssrc: mediaSsrc, sequences: sequences),
          );
        case DiscordRtcpReceiverReport(:final ssrc, :final cumulativeLost):
          _events.add(
            VoiceReceiverReportEvent(
              ssrc: ssrc,
              lossRatio: report.lossRatio,
              cumulativeLost: cumulativeLost,
            ),
          );
      }
    }
  }

  int _undecryptableFeedback = 0;

  /// The keyframe a picture-loss indication asks for. Rate-limited because
  /// the server relays one per struggling viewer and a burst of joins must
  /// not become a burst of keyframes, which would spend more bitrate than the
  /// loss did.
  void _requestKeyframe() {
    final now = DateTime.now();
    if (_lastKeyframeRequest != null &&
        now.difference(_lastKeyframeRequest!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastKeyframeRequest = now;
    _events.add(const VoiceKeyframeRequestedEvent());
  }

  DateTime? _lastKeyframeRequest;

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
    AppLog.warning(
      'voice.transport',
      '$what${detail == null ? '' : ': $detail'}',
    );
  }

  void _scheduleReconnect({Object? error}) {
    if (_closing || _failed || _reconnectTimer?.isActive == true) return;
    _diagnose('reconnecting', error);
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    // What dropped is the socket, not the session. A resume continues the
    // same one: the same key, the same SSRC, the same media server, over a
    // UDP path that never went anywhere — and Discord answers a resume with
    // RESUMED alone, never a second session description. Tearing the media
    // plane down here left nothing to rebuild it from, and a share went on
    // encoding into a cipher that no longer existed, reporting sixty healthy
    // frames a second that never reached the wire.
    //
    // A redial that must identify afresh gets everything back, since it
    // negotiates a new key and SSRC and the old ones would only mislead it.
    if (!_protocol.canResume) {
      _keepaliveTimer?.cancel();
      _keepaliveTimer = null;
      _protocol.dropSession();
      _mediaTransport.reset();
      _replaceTransportCipher(null);
    }
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
