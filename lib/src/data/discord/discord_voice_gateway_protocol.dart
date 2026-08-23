import '../../domain/video_encoder.dart';
import '../../domain/voice_connection.dart';

import 'discord_gateway_rules.dart';
import 'discord_voice_transport_cipher.dart';
import 'discord_voice_udp_transport.dart';

final class DiscordVoiceReady {
  const DiscordVoiceReady({
    required this.ssrc,
    required this.ip,
    required this.port,
    required this.modes,
  });

  final int ssrc;
  final String ip;
  final int port;
  final List<String> modes;

  static DiscordVoiceReady? tryParse(Map<String, Object?> data) {
    final ssrc = data['ssrc'] as int?;
    final ip = data['ip'] as String?;
    final port = data['port'] as int?;
    final rawModes = data['modes'];
    if (ssrc == null ||
        ip == null ||
        ip.isEmpty ||
        port == null ||
        rawModes is! List) {
      return null;
    }
    return DiscordVoiceReady(
      ssrc: ssrc,
      ip: ip,
      port: port,
      modes: rawModes.whereType<String>().toList(growable: false),
    );
  }
}

final class DiscordVoiceSessionDescription {
  const DiscordVoiceSessionDescription({
    required this.mode,
    required this.secretKey,
    required this.daveProtocolVersion,
  });

  final String mode;
  final List<int> secretKey;
  final int daveProtocolVersion;

  static DiscordVoiceSessionDescription? tryParse(Map<String, Object?> data) {
    final mode = data['mode'] as String?;
    final rawKey = data['secret_key'];
    final daveVersion = data['dave_protocol_version'] as int? ?? 0;
    if (mode == null || mode.isEmpty || rawKey is! List) return null;
    final key = rawKey.whereType<int>().toList(growable: false);
    if (key.length != rawKey.length) return null;
    return DiscordVoiceSessionDescription(
      mode: mode,
      secretKey: key,
      daveProtocolVersion: daveVersion,
    );
  }
}

abstract final class DiscordVoiceGatewayOpcode {
  static const identify = 0;
  static const selectProtocol = 1;
  static const ready = 2;
  static const heartbeat = 3;
  static const sessionDescription = 4;
  static const speaking = 5;
  static const heartbeatAck = 6;
  static const resume = 7;
  static const hello = 8;
  static const resumed = 9;
  static const clientVideo = 12;
  static const clientDisconnect = 13;
}

/// What the protocol decided; the client's job is to carry it out.
sealed class DiscordVoiceGatewayAction {
  const DiscordVoiceGatewayAction();
}

/// Send this frame over the socket.
final class DiscordVoiceGatewaySend extends DiscordVoiceGatewayAction {
  const DiscordVoiceGatewaySend(this.payload);

  final Map<String, Object?> payload;
}

/// (Re)start the heartbeat timer at this interval.
final class DiscordVoiceGatewayScheduleHeartbeat
    extends DiscordVoiceGatewayAction {
  const DiscordVoiceGatewayScheduleHeartbeat(this.interval);

  final Duration interval;
}

/// Redial the endpoint after the reconnect delay. [error] is what to report
/// while that happens.
final class DiscordVoiceGatewayReconnect extends DiscordVoiceGatewayAction {
  const DiscordVoiceGatewayReconnect({this.error});

  final Object? error;
}

/// The session ended, and Discord will issue a new one through the main
/// gateway rather than this socket.
///
/// The driver reports the state and waits; redialling would only reuse a
/// token that is already dead.
final class DiscordVoiceGatewayAwaitCredentials
    extends DiscordVoiceGatewayAction {
  const DiscordVoiceGatewayAwaitCredentials(this.error);

  final Object error;
}

/// The connection closed in a way a redial cannot fix.
final class DiscordVoiceGatewayFail extends DiscordVoiceGatewayAction {
  const DiscordVoiceGatewayFail(this.error);

  final Object error;
}

/// Hand this event to the session's listeners.
final class DiscordVoiceGatewayDispatch extends DiscordVoiceGatewayAction {
  const DiscordVoiceGatewayDispatch(this.event);

  final VoiceSignalingEvent event;
}

/// Punch the UDP hole for this READY, then hand the address it produced back
/// through [DiscordVoiceGatewayProtocol.udpDiscovered].
///
/// The one step of the handshake that needs real I/O, which is why it is an
/// instruction to the driver rather than a decision the protocol applies
/// itself.
final class DiscordVoiceGatewayDiscoverUdp extends DiscordVoiceGatewayAction {
  const DiscordVoiceGatewayDiscoverUdp({required this.ready, required this.mode});

  final DiscordVoiceReady ready;
  final String mode;
}

/// The session is negotiated. The driver builds the media plane from it and
/// tells the listeners the transport is ready.
final class DiscordVoiceGatewayTransportReady
    extends DiscordVoiceGatewayAction {
  const DiscordVoiceGatewayTransportReady(this.session);

  final VoiceTransportSession session;
}

/// Close codes Discord's voice gateway closes a connection with, and what
/// each one means where this client has met it.
///
/// The call socket and the Go Live stream socket are closed by the same
/// server with the same codes, so they share this vocabulary.
abstract final class DiscordVoiceCloseCodes {
  /// The identify named a session the server does not recognise: a session id
  /// from before the main gateway reconnected, a resume into a session
  /// Discord had already replaced, or, on a stream socket, the guild id
  /// where the stream's own RTC server id belongs.
  static const sessionInvalid = 4006;

  /// The voice server moved, or the call was moved. Discord hands out fresh
  /// credentials for the next one; a client gone silent long enough for its
  /// NAT mapping to expire is closed with this as well.
  static const serverMoved = 4014;

  /// The connection did not match what its identify claimed: a stream socket
  /// that did not declare its stream or its screen, or one identifying with
  /// the voice channel instead of the stream's RTC channel.
  static const identifyRefused = 4017;

  /// The main gateway session this connection identified with expired, which
  /// is what happens when that gateway reconnected and was handed a new one.
  static const sessionExpired = 4022;
}

final class DiscordVoiceGatewayProtocol {
  DiscordVoiceGatewayProtocol({
    required this.credentials,
    required this.maxDaveProtocolVersion,
    this.carriesVideo = false,
    this.streamKey,
  });

  static const preferredModes = DiscordVoiceTransportMode.preferred;

  final VoiceServerCredentials credentials;
  final int maxDaveProtocolVersion;

  /// Whether this connection exists to carry a screen share.
  ///
  /// A Go Live socket has to say so when it identifies. A call's does not:
  /// a camera on a call is announced later, with opcode 12, on a connection
  /// that was opened for audio.
  final bool carriesVideo;

  /// Which stream this connection is for, when it is for one.
  ///
  /// A stream server carries many at once and is told which by key. Nothing
  /// else in the identify names one: the RTC server id it was given is per
  /// stream, but the server answers an identify without the key with
  /// `identifyRefused`.
  final String? streamKey;
  int sequenceAck = -1;

  final DiscordGatewayHeartbeatWatchdog _heartbeat =
      DiscordGatewayHeartbeatWatchdog();

  /// Whether a redial should resume this session rather than identify
  /// afresh.
  ///
  /// True once Discord has accepted the session (a RESUMED answer, or a
  /// session description). Withdrawn when the session is too far behind on
  /// heartbeats to still be recognised, or when its secrets prove stale.
  bool _canResume = false;
  bool get canResume => _canResume;

  /// The audio SSRC Discord handed this session, or null before the voice
  /// `READY`.
  ///
  /// A camera sends on the one above it, which is how the desktop client
  /// derives its own video SSRC rather than being told one.
  int? _audioSsrc;
  int? get audioSsrc => _audioSsrc;

  String? _mode;
  DiscordVoiceIpDiscovery? _discovered;
  VoiceTransportSession? _session;

  /// The negotiated session, or null while the handshake runs.
  VoiceTransportSession? get session => _session;

  /// Every SSRC Discord has attributed to a user, from opcodes 5 and 12.
  final Map<int, String> _userIdsBySsrc = {};

  /// Video SSRC to whoever announced it, from opcode 12.
  final Map<int, String> _videoSsrcOwners = {};

  String? userIdForSsrc(int ssrc) => _userIdsBySsrc[ssrc];

  /// Who sends on a video SSRC, once their opcode 12 has said so.
  String? userIdForVideoSsrc(int ssrc) => _videoSsrcOwners[ssrc];

  /// Decides what an inbound frame means.
  ///
  /// Never touches a socket or a timer: the driver applies whatever comes
  /// back, in order.
  List<DiscordVoiceGatewayAction> accept(Map<String, Object?> payload) {
    acceptSequence(payload['seq']);
    final opcode = payload['op'];
    final data = payload['d'];
    switch (opcode) {
      case DiscordVoiceGatewayOpcode.ready:
        if (data is Map) return _acceptReady(data.cast<String, Object?>());
      case DiscordVoiceGatewayOpcode.sessionDescription:
        if (data is Map) {
          return _acceptSessionDescription(data.cast<String, Object?>());
        }
      case DiscordVoiceGatewayOpcode.speaking:
        if (data is Map) return _acceptSpeaking(data.cast<String, Object?>());
      case DiscordVoiceGatewayOpcode.heartbeatAck:
        _heartbeat.acknowledge();
      case DiscordVoiceGatewayOpcode.hello:
        if (data is Map) return _acceptHello(data.cast<String, Object?>());
      case DiscordVoiceGatewayOpcode.resumed:
        _canResume = true;
        return const [
          DiscordVoiceGatewayDispatch(
            VoiceSignalingStatusEvent(VoiceConnectionStatus.ready),
          ),
        ];
      case DiscordVoiceGatewayOpcode.clientVideo:
        if (data is Map) _acceptClientVideo(data.cast<String, Object?>());
      case DiscordVoiceGatewayOpcode.clientDisconnect:
        if (data is Map) {
          return _acceptClientDisconnect(data.cast<String, Object?>());
        }
    }
    return const [];
  }

  /// Decides what a due heartbeat means. The driver calls this from its
  /// timer and applies the result.
  DiscordVoiceGatewayAction heartbeatDue() {
    if (_heartbeat.hasExceededTolerance) {
      // Not resumable: a session this far behind is one Discord has already
      // stopped recognising, and resuming into it is answered with
      // `sessionInvalid`.
      _canResume = false;
      return DiscordVoiceGatewayReconnect(
        error: StateError(
          'Discord did not acknowledge '
          '${_heartbeat.unacknowledgedCount} heartbeats',
        ),
      );
    }
    _heartbeat.recordSent();
    return DiscordVoiceGatewaySend(
      heartbeat(DateTime.now().millisecondsSinceEpoch),
    );
  }

  /// Triage for the code the server closed the socket with.
  DiscordVoiceGatewayAction closedWithCode(int? code) {
    if (code != null && _sessionEndedCodes.contains(code)) {
      return DiscordVoiceGatewayAwaitCredentials(
        StateError('Discord ended the voice session (code $code)'),
      );
    }
    if (code != null && _terminalCloseCodes.contains(code)) {
      return DiscordVoiceGatewayFail(
        StateError('Discord voice connection closed with code $code'),
      );
    }
    return const DiscordVoiceGatewayReconnect();
  }

  /// A session Discord ended but will re-issue, and none of them is an error
  /// to show somebody: the main gateway answers a ping with a fresh
  /// VOICE_SERVER_UPDATE and the connection is rebuilt from it. Redialling
  /// this endpoint would only reuse a token that is already dead, so this
  /// reports the state and waits to be handed a new one.
  static const _sessionEndedCodes = {
    DiscordVoiceCloseCodes.sessionInvalid,
    DiscordVoiceCloseCodes.serverMoved,
    DiscordVoiceCloseCodes.sessionExpired,
  };

  /// Codes a redial cannot fix: the credential was rejected, the session
  /// was refused, or the protocol was used wrongly enough that Discord
  /// wants a new connection rather than a retry of this one.
  static const _terminalCloseCodes = {
    DiscordGatewayCloseCodes.authenticationFailed,
    4009,
    4011,
    DiscordVoiceCloseCodes.identifyRefused,
    4020,
    4021,
  };

  /// Continues the handshake after the driver punched the UDP hole: the
  /// address it learned is the one SELECT_PROTOCOL announces.
  List<DiscordVoiceGatewayAction> udpDiscovered(DiscordVoiceIpDiscovery discovered) {
    _discovered = discovered;
    final mode = _mode;
    if (mode == null) return const [];
    return [
      DiscordVoiceGatewaySend(
        selectProtocol(
          address: discovered.address,
          port: discovered.port,
          mode: mode,
        ),
      ),
    ];
  }

  /// Withdraws resume eligibility: the session's secrets proved stale, and
  /// the next connect must identify afresh rather than resume into a
  /// session Discord has replaced.
  void revokeResume() => _canResume = false;

  /// Drops what a redial would learn again anyway: discovery, the
  /// negotiated session, and the speaking roster (opcode 5 re-adds anybody
  /// the moment they talk). Video owners are kept: a resume does not
  /// re-announce peers whose cameras did not change, and dropping them
  /// would black out tiles that are still being sent. Identity and resume
  /// eligibility survive as well, for the redial.
  void dropSession() {
    _discovered = null;
    _session = null;
    _userIdsBySsrc.clear();
  }

  /// `server_id` is the guild for guild voice and the channel for a DM or
  /// group-DM call (R08) — the credentials know which, so the identify body
  /// does not have to.
  /// `channel_id` and `video` are what the desktop client sends alongside the
  /// four identifying fields.
  ///
  /// A Go Live connection declares the stream it is there to carry. Discord
  /// closes one that does not with `identifyRefused` the moment it finishes
  /// connecting, which is what every share and every attempt to watch
  /// somebody was doing. `rid` "100" and quality 100 are the single
  /// full-quality layer; simulcast would list more.
  Map<String, Object?> identify() => {
    'op': 0,
    'd': {
      'server_id': credentials.serverId,
      // A stream socket carries no channel: it belongs to the RTC server the
      // create named, not to a room.
      if (!carriesVideo) 'channel_id': credentials.channelId,
      'max_dave_protocol_version': maxDaveProtocolVersion,
      'user_id': credentials.userId,
      'session_id': credentials.sessionId,
      'token': credentials.token,
      'video': carriesVideo,
      if (carriesVideo)
        // A screen, not a camera: the type names what is being sent, and a
        // share announced as video is refused.
        'streams': const [
          {'type': 'screen', 'rid': '100', 'quality': 100},
        ],
    },
  };

  Map<String, Object?> resume() => {
    'op': 7,
    'd': {
      'server_id': credentials.serverId,
      'session_id': credentials.sessionId,
      'token': credentials.token,
      'seq_ack': sequenceAck,
    },
  };

  Map<String, Object?> heartbeat(int nonce) => {
    'op': 3,
    'd': {'t': nonce, 'seq_ack': sequenceAck},
  };

  Map<String, Object?> selectProtocol({
    required String address,
    required int port,
    required String mode,
  }) => {
    'op': 1,
    'd': {
      'protocol': 'udp',
      'data': {'address': address, 'port': port, 'mode': mode},
    },
  };

  Map<String, Object?> speaking({required int ssrc, required bool enabled}) => {
    'op': 5,
    'd': {'speaking': enabled ? 1 : 0, 'delay': 0, 'ssrc': ssrc},
  };

  /// Opcode 12, which declares the SSRCs this session's camera will send on.
  ///
  /// The three are not negotiated: the desktop client derives them from the
  /// audio SSRC the voice `READY` handed out — video is one above it and the
  /// retransmission stream one above that — and announces the result. A client
  /// that picked its own numbers would send on SSRCs the server is not
  /// forwarding.
  ///
  /// Turning the camera off is the same frame with [enabled] false: the stream
  /// stays declared and inactive, which is what the renderer sends, rather than
  /// the SSRCs being withdrawn.
  Map<String, Object?> video({
    required int audioSsrc,
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    final videoSsrc = audioSsrc + 1;
    return {
      'op': 12,
      'd': {
        'audio_ssrc': audioSsrc,
        'video_ssrc': videoSsrc,
        'rtx_ssrc': audioSsrc + 2,
        'streams': [
          {
            'type': 'video',
            // The single-stream rid the client falls back to when it has not
            // been told a simulcast layout; Flucord never sends more than one.
            'rid': '100',
            'ssrc': videoSsrc,
            'active': enabled,
            'quality': 100,
            'rtx_ssrc': audioSsrc + 2,
            'max_bitrate': settings.bitrate,
            'max_framerate': settings.framesPerSecond,
            'max_resolution': {
              'type': 'fixed',
              'width': settings.width,
              'height': settings.height,
            },
          },
        ],
      },
    };
  }

  /// The SSRC a camera's RTP goes out on, given the audio one.
  static int videoSsrcFor(int audioSsrc) => audioSsrc + 1;

  void acceptSequence(Object? value) {
    if (value is int) sequenceAck = value;
  }

  String? selectMode(List<String> supported) {
    for (final mode in preferredModes) {
      if (supported.contains(mode)) return mode;
    }
    return null;
  }

  List<DiscordVoiceGatewayAction> _acceptHello(Map<String, Object?> data) {
    final rawInterval = data['heartbeat_interval'];
    if (rawInterval is! num || rawInterval <= 0) return const [];
    // A fresh HELLO starts a fresh count: whatever the previous connection
    // was owed does not carry into this one.
    _heartbeat.acknowledge();
    return [
      DiscordVoiceGatewayScheduleHeartbeat(
        Duration(milliseconds: rawInterval.round()),
      ),
    ];
  }

  List<DiscordVoiceGatewayAction> _acceptReady(Map<String, Object?> data) {
    final ready = DiscordVoiceReady.tryParse(data);
    if (ready == null) {
      return const [
        DiscordVoiceGatewayFail(
          FormatException('Invalid Discord voice Ready payload'),
        ),
      ];
    }
    final mode = selectMode(ready.modes);
    if (mode == null) {
      return [
        DiscordVoiceGatewayFail(
          StateError('Discord voice server offered no supported AEAD mode'),
        ),
      ];
    }
    _audioSsrc = ready.ssrc;
    _mode = mode;
    _discovered = null;
    return [
      DiscordVoiceGatewayDiscoverUdp(ready: ready, mode: mode),
    ];
  }

  List<DiscordVoiceGatewayAction> _acceptSessionDescription(
    Map<String, Object?> data,
  ) {
    final description = DiscordVoiceSessionDescription.tryParse(data);
    final ssrc = _audioSsrc;
    final mode = _mode;
    final discovered = _discovered;
    // A description with no handshake behind it means Discord and this client
    // disagree about where the session is: nothing downstream could be built
    // from it.
    if (description == null || ssrc == null || mode == null || discovered == null) {
      return const [
        DiscordVoiceGatewayFail(
          FormatException('Invalid Discord voice session description'),
        ),
      ];
    }
    if (description.mode != mode ||
        description.daveProtocolVersion > maxDaveProtocolVersion) {
      return [
        DiscordVoiceGatewayFail(
          StateError('Discord selected an unsupported voice protocol'),
        ),
      ];
    }
    _canResume = true;
    final session = VoiceTransportSession(
      guildId: credentials.guildId,
      ssrc: ssrc,
      address: discovered.address,
      port: discovered.port,
      mode: mode,
      secretKey: description.secretKey,
      daveProtocolVersion: description.daveProtocolVersion,
    );
    _session = session;
    return [DiscordVoiceGatewayTransportReady(session)];
  }

  List<DiscordVoiceGatewayAction> _acceptSpeaking(Map<String, Object?> data) {
    final userId = data['user_id'];
    final ssrc = data['ssrc'];
    final speakingFlags = data['speaking'];
    if (userId is! String ||
        ssrc is! int ||
        ssrc < 0 ||
        ssrc > 0xffffffff ||
        speakingFlags is! int) {
      return const [];
    }
    _userIdsBySsrc[ssrc] = userId;
    return [
      DiscordVoiceGatewayDispatch(
        VoiceSpeakingEvent(
          userId: userId,
          ssrc: ssrc,
          speakingFlags: speakingFlags,
        ),
      ),
    ];
  }

  /// Opcode 12 announces a peer's media layout, not their departure.
  ///
  /// It arrives when someone joins or changes their video state and carries the
  /// SSRCs they will send on. Taking `audio_ssrc` from here means a peer is
  /// resolvable before they ever speak, where opcode 5 only reveals them at
  /// their first speaking flag.
  void _acceptClientVideo(Map<String, Object?> data) {
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

  List<DiscordVoiceGatewayAction> _acceptClientDisconnect(
    Map<String, Object?> data,
  ) {
    final userId = data['user_id'];
    if (userId is! String) return const [];
    _userIdsBySsrc.removeWhere((_, mappedUserId) => mappedUserId == userId);
    _videoSsrcOwners.removeWhere((_, mappedUserId) => mappedUserId == userId);
    return [DiscordVoiceGatewayDispatch(VoiceUserDisconnectedEvent(userId))];
  }
}
