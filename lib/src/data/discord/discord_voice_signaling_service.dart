import 'dart:async';
import 'dart:typed_data';

import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_call_state_roster.dart';
import 'discord_rtp_packet.dart';
import 'discord_gateway_client.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_session_assembler.dart';
import 'discord_voice_state_roster.dart';

typedef DiscordVoiceClientFactory =
    DiscordVoiceClient Function(
      VoiceServerCredentials credentials,
      VoiceDaveService? daveService,
    );

final class DiscordVoiceSignalingService
    implements VoiceSignalingService, VoiceAudioTransport {
  /// [callGateway] is the private-call plane and is optional on purpose: a bot
  /// session speaks opcode 4 but can never place a DM call, so a transport that
  /// cannot ring simply does not supply one and [joinCall] reports the refusal
  /// instead of a method existing that would always throw.
  DiscordVoiceSignalingService({
    required DiscordVoiceStateGateway mainGateway,
    required VoiceDaveService? nativeDaveService,
    this._callGateway,
    DiscordVoiceClientFactory? voiceClientFactory,
  }) : _gateway = mainGateway,
       _daveService = nativeDaveService,
       _clientFactory = voiceClientFactory ?? _createVoiceClient {
    _gatewaySubscription = _gateway.events.listen(_onGatewayEvent);
  }

  final DiscordVoiceStateGateway _gateway;
  final DiscordCallGateway? _callGateway;
  final VoiceDaveService? _daveService;
  final DiscordVoiceClientFactory _clientFactory;
  final DiscordVoiceSessionAssembler _assembler =
      DiscordVoiceSessionAssembler();
  final DiscordVoiceStateRoster _roster = DiscordVoiceStateRoster();
  final StreamController<void> _seatedChanges = StreamController.broadcast();
  final DiscordCallStateRoster _callRoster = DiscordCallStateRoster();
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _remoteAudio =
      StreamController.broadcast();
  final Map<VoiceSessionKey, String> _desiredChannels = {};
  final Set<VoiceSessionKey> _pingedSessions = <VoiceSessionKey>{};
  final Map<VoiceSessionKey, int> _generations = {};
  final Map<VoiceSessionKey, DiscordVoiceClient> _clients = {};
  VoiceConnectionStatus _currentStatus = VoiceConnectionStatus.disconnected;
  VoiceTransportSession? _currentSession;
  final Map<VoiceSessionKey, StreamSubscription<VoiceSignalingEvent>>
  _clientSubscriptions = {};
  final Map<VoiceSessionKey, StreamSubscription<VoiceRemoteOpusFrame>>
  _audioSubscriptions = {};
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
  String? _currentUserId;
  VoiceSessionKey? _activeSession;
  bool _closed = false;

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _remoteAudio.stream;

  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) => _join(
    VoiceSessionKey.guild(guildId),
    channelId: channelId,
    selfMute: selfMute,
    selfDeaf: selfDeaf,
    selfVideo: selfVideo,
  );

  @override
  Future<void> leaveVoiceChannel(String guildId) =>
      _leave(VoiceSessionKey.guild(guildId));

  /// Joins a call in a DM or group DM.
  ///
  /// The media path is the one guild voice already uses; only the signalling
  /// differs, so this shares every step below the session key.
  Future<void> joinCall({
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) {
    if (_callGateway == null) {
      _emit(
        VoiceSignalingStatusEvent(
          VoiceConnectionStatus.failure,
          error: StateError('This session cannot join private calls'),
        ),
      );
      return Future<void>.value();
    }
    return _join(
      VoiceSessionKey.privateCall(channelId),
      channelId: channelId,
      selfMute: selfMute,
      selfDeaf: selfDeaf,
      selfVideo: selfVideo,
    );
  }

  Future<void> leaveCall(String channelId) =>
      _leave(VoiceSessionKey.privateCall(channelId));

  Future<void> _join(
    VoiceSessionKey key, {
    required String channelId,
    required bool selfMute,
    required bool selfDeaf,
    bool selfVideo = false,
  }) async {
    if (_closed) throw StateError('Voice signaling service is closed');
    // DAVE is not a precondition for being in a voice channel. Discord's own
    // client identifies with `max_dave_protocol_version: 0` whenever secure
    // frames are unavailable and the room runs on the transport cipher alone,
    // so refusing the join outright — the old behaviour — turned a missing
    // native library into "voice does not work" with the join never sent.
    if (_currentUserId == null) {
      _emit(
        VoiceSignalingStatusEvent(
          VoiceConnectionStatus.failure,
          error: StateError('Discord Gateway is not ready for voice'),
        ),
      );
      return;
    }
    _activeSession = key;
    if (_desiredChannels[key] == channelId) {
      _sendVoiceState(
        key,
        channelId,
        selfMute: selfMute,
        selfDeaf: selfDeaf,
        selfVideo: selfVideo,
      );
      return;
    }
    _desiredChannels[key] = channelId;
    _generations[key] = (_generations[key] ?? 0) + 1;
    _assembler.clear(key);
    _emit(const VoiceSignalingStatusEvent(VoiceConnectionStatus.joining));
    // The people already sitting in the channel were announced at bootstrap and
    // will not be announced again, so the roster is replayed here or the room
    // renders empty until somebody else moves.
    for (final state in _seatedIn(key, channelId)) {
      _emit(state);
    }
    _sendVoiceState(
      key,
      channelId,
      selfMute: selfMute,
      selfDeaf: selfDeaf,
      selfVideo: selfVideo,
    );
  }

  Future<void> _leave(VoiceSessionKey key) async {
    _desiredChannels.remove(key);
    _generations[key] = (_generations[key] ?? 0) + 1;
    _assembler.clear(key);
    _sendVoiceState(key, null);
    await _closeClient(key);
    if (_activeSession == key) _activeSession = null;
    _emit(const VoiceSignalingStatusEvent(VoiceConnectionStatus.disconnected));
  }

  void _sendVoiceState(
    VoiceSessionKey key,
    String? channelId, {
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) {
    final guildId = key.guildId;
    if (guildId != null) {
      _gateway.updateVoiceState(
        guildId: guildId,
        channelId: channelId,
        selfMute: selfMute,
        selfDeaf: selfDeaf,
        selfVideo: selfVideo,
      );
      return;
    }
    _callGateway?.updateCallVoiceState(
      channelId: key.callChannelId!,
      connected: channelId != null,
      selfMute: selfMute,
      selfDeaf: selfDeaf,
      selfVideo: selfVideo,
    );
  }

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => {
    ..._roster.seatedByChannel,
    ..._callRoster.seatedByChannel,
  };

  @override
  Stream<void> get seatedChanges => _seatedChanges.stream;

  List<VoiceParticipantStateEvent> _seatedIn(
    VoiceSessionKey key,
    String channelId,
  ) => key.isPrivateCall
      ? _callRoster.participantsIn(channelId)
      : _roster.participantsIn(guildId: key.guildId!, channelId: channelId);

  void _onGatewayEvent(DiscordGatewayEvent event) {
    if (event is! DiscordGatewayDispatch) return;
    // Every guild is tracked, not just the one being joined: which channel the
    // user will pick is unknown while the bulk snapshots are arriving. The
    // roster is also fed before the current user is known, because the
    // `GUILD_CREATE` burst that carries the occupants arrives *during*
    // bootstrap, minutes before the workspace resolves and names us.
    final applied = _roster.accept(eventName: event.name, data: event.data);
    if (applied.isNotEmpty && !_seatedChanges.isClosed) {
      _seatedChanges.add(null);
    }
    for (final state in applied) {
      if (_desiredChannels.containsKey(VoiceSessionKey.guild(state.guildId!))) {
        _emit(state);
      }
    }
    for (final change in _callRoster.accept(
      eventName: event.name,
      data: event.data,
    )) {
      final key = VoiceSessionKey.privateCall(change.channelId);
      if (_desiredChannels.containsKey(key)) _emit(change.state);
    }
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;
    final credentials = _assembler.accept(
      eventName: event.name,
      data: event.data,
      currentUserId: currentUserId,
    );
    if (credentials == null) return;
    final key = credentials.sessionKey;
    if (_desiredChannels[key] != credentials.channelId) return;
    unawaited(_startVoiceClient(credentials, _generations[key] ?? 0));
  }

  /// Pokes the main gateway when a voice socket drops but intends to come back.
  ///
  /// R08: the desktop client answers a will-reconnect disconnect with opcode 5
  /// `VOICE_SERVER_PING`, which is how the server learns to re-issue a
  /// `VOICE_SERVER_UPDATE` for a session it still believes is live. Without it
  /// the reconnecting voice client redials an endpoint whose token may already
  /// have been rotated.
  /// A failing voice socket can report `reconnecting` repeatedly, so the ping
  /// fires on the transition into that state and not on every repeat. Left
  /// unguarded it turns one broken voice connection into a flood on the main
  /// gateway, which is the socket carrying every message.
  @override
  VoiceConnectionStatus get currentStatus => _currentStatus;

  @override
  VoiceTransportSession? get currentSession => _currentSession;

  void _onClientEvent(VoiceSessionKey key, VoiceSignalingEvent event) {
    // Only the session being listened to speaks for the client's state: a
    // second connection winding down must not report the first as gone.
    if (key == _activeSession) {
      if (event is VoiceSignalingStatusEvent) _currentStatus = event.status;
      if (event is VoiceTransportReadyEvent) _currentSession = event.session;
    }
    if (event is VoiceSignalingStatusEvent) {
      final wasReconnecting = _pingedSessions.contains(key);
      final isReconnecting = event.status == VoiceConnectionStatus.reconnecting;
      if (isReconnecting && !wasReconnecting) {
        if (_desiredChannels.containsKey(key)) {
          _pingedSessions.add(key);
          _gateway.pingVoiceServer();
        }
      } else if (!isReconnecting) {
        _pingedSessions.remove(key);
      }
    }
    _emit(event);
  }

  Future<void> _startVoiceClient(
    VoiceServerCredentials credentials,
    int generation,
  ) async {
    final key = credentials.sessionKey;
    await _closeClient(key);
    if (_closed ||
        generation != _generations[key] ||
        _desiredChannels[key] != credentials.channelId) {
      return;
    }
    final client = _clientFactory(credentials, _daveService);
    _clients[key] = client;
    _clientSubscriptions[key] = client.events.listen(
      (event) => _onClientEvent(key, event),
    );
    if (client case final VoiceAudioTransport audioTransport) {
      _audioSubscriptions[key] = audioTransport.remoteAudio.listen(
        _emitRemoteAudio,
        onError: _remoteAudio.addError,
      );
    }
    _emit(VoiceCredentialsReadyEvent(credentials));
    try {
      await client.connect();
    } catch (error) {
      _emit(
        VoiceSignalingStatusEvent(VoiceConnectionStatus.failure, error: error),
      );
    }
  }

  Future<void> _closeClient(VoiceSessionKey key) async {
    await _audioSubscriptions.remove(key)?.cancel();
    await _clientSubscriptions.remove(key)?.cancel();
    await _clients.remove(key)?.close();
  }

  /// Everybody else's cameras on the session currently joined.
  ///
  /// Rebuilt on every join rather than held: the session is a different socket
  /// with different SSRCs, and a subscriber left on the old one would draw a
  /// room nobody is in.
  Stream<(String, DiscordRtpFrame)> get remoteVideo {
    final session = _activeSession;
    final client = session == null ? null : _clients[session];
    if (client is! DiscordVoiceGatewayClient) {
      return const Stream<(String, DiscordRtpFrame)>.empty();
    }
    return client.videoPackets;
  }

  /// The video plane of the session currently joined, or null when there is
  /// none — no session, or a client that cannot carry pictures.
  VoiceVideoTransport? get activeVideoTransport {
    final session = _activeSession;
    final client = session == null ? null : _clients[session];
    return client is VoiceVideoTransport ? client as VoiceVideoTransport : null;
  }

  /// Encrypts and sends one video RTP frame on the active session.
  ///
  /// The same socket and the same cipher the audio uses: a camera is another
  /// SSRC on the connection that is already open, not a second connection.
  int sendVideoFrame(DiscordRtpFrame frame) {
    final session = _activeSession;
    final client = session == null ? null : _clients[session];
    if (client is! DiscordVoiceGatewayClient) {
      throw StateError('Discord voice transport is not ready');
    }
    return client.sendAudioFrame(frame);
  }

  @override
  void sendOpusFrame(Uint8List opusFrame) {
    final session = _activeSession;
    final client = session == null ? null : _clients[session];
    if (client is! VoiceAudioTransport) {
      throw StateError('Discord voice media transport is not ready');
    }
    (client as VoiceAudioTransport).sendOpusFrame(opusFrame);
  }

  @override
  Future<void> finishSpeaking() async {
    final session = _activeSession;
    final client = session == null ? null : _clients[session];
    if (client is VoiceAudioTransport) {
      await (client as VoiceAudioTransport).finishSpeaking();
    }
  }

  void _emit(VoiceSignalingEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _emitRemoteAudio(VoiceRemoteOpusFrame frame) {
    if (!_remoteAudio.isClosed) _remoteAudio.add(frame);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _gatewaySubscription.cancel();
    for (final key in _clients.keys.toList(growable: false)) {
      await _closeClient(key);
    }
    _assembler.clearAll();
    _roster.clearAll();
    _callRoster.clearAll();
    await _remoteAudio.close();
    await _events.close();
  }

  static DiscordVoiceClient _createVoiceClient(
    VoiceServerCredentials credentials,
    VoiceDaveService? daveService,
  ) => DiscordVoiceGatewayClient(
    credentials: credentials,
    // Zero is what the desktop client sends when it cannot do secure frames,
    // and it is what tells Discord to leave the room on transport encryption
    // rather than negotiating an MLS group this session could not join.
    maxDaveProtocolVersion: daveService?.maxProtocolVersion ?? 0,
    daveService: daveService,
  );
}
