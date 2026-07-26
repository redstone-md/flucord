import 'dart:async';
import 'dart:typed_data';

import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_gateway_client.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_session_assembler.dart';
import 'discord_voice_state_roster.dart';

typedef DiscordVoiceClientFactory =
    DiscordVoiceClient Function(
      VoiceServerCredentials credentials,
      VoiceDaveService daveService,
    );

final class DiscordVoiceSignalingService
    implements VoiceSignalingService, VoiceAudioTransport {
  DiscordVoiceSignalingService({
    required DiscordVoiceStateGateway mainGateway,
    required VoiceDaveService? nativeDaveService,
    DiscordVoiceClientFactory? voiceClientFactory,
  }) : _gateway = mainGateway,
       _daveService = nativeDaveService,
       _clientFactory = voiceClientFactory ?? _createVoiceClient {
    _gatewaySubscription = _gateway.events.listen(_onGatewayEvent);
  }

  final DiscordVoiceStateGateway _gateway;
  final VoiceDaveService? _daveService;
  final DiscordVoiceClientFactory _clientFactory;
  final DiscordVoiceSessionAssembler _assembler =
      DiscordVoiceSessionAssembler();
  final DiscordVoiceStateRoster _roster = DiscordVoiceStateRoster();
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _remoteAudio =
      StreamController.broadcast();
  final Map<String, String> _desiredChannels = {};
  final Set<String> _pingedGuilds = <String>{};
  final Map<String, int> _generations = {};
  final Map<String, DiscordVoiceClient> _clients = {};
  final Map<String, StreamSubscription<VoiceSignalingEvent>>
  _clientSubscriptions = {};
  final Map<String, StreamSubscription<VoiceRemoteOpusFrame>>
  _audioSubscriptions = {};
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
  String? _currentUserId;
  String? _activeGuildId;
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
  }) async {
    if (_closed) throw StateError('Voice signaling service is closed');
    final daveService = _daveService;
    if (daveService == null || daveService.maxProtocolVersion <= 0) {
      _emit(
        VoiceSignalingStatusEvent(
          VoiceConnectionStatus.failure,
          error: StateError('DAVE voice encryption is unavailable'),
        ),
      );
      return;
    }
    if (_currentUserId == null) {
      _emit(
        VoiceSignalingStatusEvent(
          VoiceConnectionStatus.failure,
          error: StateError('Discord Gateway is not ready for voice'),
        ),
      );
      return;
    }
    _activeGuildId = guildId;
    if (_desiredChannels[guildId] == channelId) {
      _gateway.updateVoiceState(
        guildId: guildId,
        channelId: channelId,
        selfMute: selfMute,
        selfDeaf: selfDeaf,
      );
      return;
    }
    _desiredChannels[guildId] = channelId;
    _generations[guildId] = (_generations[guildId] ?? 0) + 1;
    _assembler.clear(guildId);
    _emit(const VoiceSignalingStatusEvent(VoiceConnectionStatus.joining));
    // The people already sitting in the channel were announced at bootstrap and
    // will not be announced again, so the roster is replayed here or the room
    // renders empty until somebody else moves.
    for (final state in _roster.participantsIn(
      guildId: guildId,
      channelId: channelId,
    )) {
      _emit(state);
    }
    _gateway.updateVoiceState(
      guildId: guildId,
      channelId: channelId,
      selfMute: selfMute,
      selfDeaf: selfDeaf,
    );
  }

  @override
  Future<void> leaveVoiceChannel(String guildId) async {
    _desiredChannels.remove(guildId);
    _generations[guildId] = (_generations[guildId] ?? 0) + 1;
    _assembler.clear(guildId);
    _gateway.updateVoiceState(guildId: guildId, channelId: null);
    await _closeClient(guildId);
    if (_activeGuildId == guildId) _activeGuildId = null;
    _emit(const VoiceSignalingStatusEvent(VoiceConnectionStatus.disconnected));
  }

  void _onGatewayEvent(DiscordGatewayEvent event) {
    if (event is! DiscordGatewayDispatch) return;
    // Every guild is tracked, not just the one being joined: which channel the
    // user will pick is unknown while the bulk snapshots are arriving. The
    // roster is also fed before the current user is known, because the
    // `GUILD_CREATE` burst that carries the occupants arrives *during*
    // bootstrap, minutes before the workspace resolves and names us.
    for (final state in _roster.accept(
      eventName: event.name,
      data: event.data,
    )) {
      if (_desiredChannels.containsKey(state.guildId)) _emit(state);
    }
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;
    final credentials = _assembler.accept(
      eventName: event.name,
      data: event.data,
      currentUserId: currentUserId,
    );
    if (credentials == null ||
        _desiredChannels[credentials.guildId] != credentials.channelId) {
      return;
    }
    final generation = _generations[credentials.guildId] ?? 0;
    unawaited(_startVoiceClient(credentials, generation));
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
  void _onClientEvent(String guildId, VoiceSignalingEvent event) {
    if (event is VoiceSignalingStatusEvent) {
      final wasReconnecting = _pingedGuilds.contains(guildId);
      final isReconnecting = event.status == VoiceConnectionStatus.reconnecting;
      if (isReconnecting && !wasReconnecting) {
        if (_desiredChannels.containsKey(guildId)) {
          _pingedGuilds.add(guildId);
          _gateway.pingVoiceServer();
        }
      } else if (!isReconnecting) {
        _pingedGuilds.remove(guildId);
      }
    }
    _emit(event);
  }

  Future<void> _startVoiceClient(
    VoiceServerCredentials credentials,
    int generation,
  ) async {
    final daveService = _daveService;
    if (daveService == null) return;
    await _closeClient(credentials.guildId);
    if (_closed ||
        generation != _generations[credentials.guildId] ||
        _desiredChannels[credentials.guildId] != credentials.channelId) {
      return;
    }
    final client = _clientFactory(credentials, daveService);
    _clients[credentials.guildId] = client;
    _clientSubscriptions[credentials.guildId] = client.events.listen(
      (event) => _onClientEvent(credentials.guildId, event),
    );
    if (client case final VoiceAudioTransport audioTransport) {
      _audioSubscriptions[credentials.guildId] = audioTransport.remoteAudio
          .listen(_emitRemoteAudio, onError: _remoteAudio.addError);
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

  Future<void> _closeClient(String guildId) async {
    await _audioSubscriptions.remove(guildId)?.cancel();
    await _clientSubscriptions.remove(guildId)?.cancel();
    await _clients.remove(guildId)?.close();
  }

  @override
  void sendOpusFrame(Uint8List opusFrame) {
    final guildId = _activeGuildId;
    final client = guildId == null ? null : _clients[guildId];
    if (client is! VoiceAudioTransport) {
      throw StateError('Discord voice media transport is not ready');
    }
    (client as VoiceAudioTransport).sendOpusFrame(opusFrame);
  }

  @override
  Future<void> finishSpeaking() async {
    final guildId = _activeGuildId;
    final client = guildId == null ? null : _clients[guildId];
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
    for (final guildId in _clients.keys.toList(growable: false)) {
      await _closeClient(guildId);
    }
    _assembler.clearAll();
    _roster.clearAll();
    await _remoteAudio.close();
    await _events.close();
  }

  static DiscordVoiceClient _createVoiceClient(
    VoiceServerCredentials credentials,
    VoiceDaveService daveService,
  ) => DiscordVoiceGatewayClient(
    credentials: credentials,
    maxDaveProtocolVersion: daveService.maxProtocolVersion,
    daveService: daveService,
  );
}
