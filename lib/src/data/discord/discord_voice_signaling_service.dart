import 'dart:async';
import 'dart:typed_data';

import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_gateway_client.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_session_assembler.dart';

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
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _remoteAudio =
      StreamController.broadcast();
  final Map<String, String> _desiredChannels = {};
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
    if (event is! DiscordGatewayDispatch || _currentUserId == null) return;
    _emitParticipantState(event);
    final credentials = _assembler.accept(
      eventName: event.name,
      data: event.data,
      currentUserId: _currentUserId!,
    );
    if (credentials == null ||
        _desiredChannels[credentials.guildId] != credentials.channelId) {
      return;
    }
    final generation = _generations[credentials.guildId] ?? 0;
    unawaited(_startVoiceClient(credentials, generation));
  }

  void _emitParticipantState(DiscordGatewayDispatch event) {
    if (event.name != 'VOICE_STATE_UPDATE') return;
    final data = event.data;
    final guildId = data['guild_id'];
    final userId = data['user_id'];
    if (guildId is! String ||
        userId is! String ||
        !_desiredChannels.containsKey(guildId)) {
      return;
    }
    final channelId = data['channel_id'];
    if (channelId != null && channelId is! String) return;
    _emit(
      VoiceParticipantStateEvent(
        userId: userId,
        guildId: guildId,
        channelId: channelId as String?,
        selfMuted: data['self_mute'] == true,
        selfDeafened: data['self_deaf'] == true,
        serverMuted: data['mute'] == true,
        serverDeafened: data['deaf'] == true,
        isStreaming: data['self_stream'] == true,
        isVideoEnabled: data['self_video'] == true,
      ),
    );
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
    _clientSubscriptions[credentials.guildId] = client.events.listen(_emit);
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
