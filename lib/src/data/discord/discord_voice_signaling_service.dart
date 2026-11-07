import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/voice_audio.dart';
import '../../domain/voice_connection.dart';
import 'discord_call_state_roster.dart';
import 'discord_rtp_packet.dart';
import 'discord_gateway_client.dart';
import 'discord_voice_gateway_client.dart';
import 'discord_voice_gateway_protocol.dart';
import 'discord_voice_session_assembler.dart';
import 'discord_voice_socket_factory.dart';
import 'discord_voice_state_roster.dart';
import '../../app_log.dart';

final class DiscordVoiceSignalingService
    implements VoiceSignalingService, VoiceAudioTransport {
  /// [callGateway] is the private-call plane and is optional on purpose: a bot
  /// session speaks opcode 4 but can never place a DM call, so a transport that
  /// cannot ring simply does not supply one and [joinCall] reports the refusal
  /// instead of a method existing that would always throw.
  DiscordVoiceSignalingService({
    required DiscordVoiceStateGateway mainGateway,
    required DiscordVoiceSocketFactory socketFactory,
    this._callGateway,
    Duration reissueFallbackDelay = const Duration(seconds: 2),
  }) : _gateway = mainGateway,
       _socketFactory = socketFactory,
       _reissueFallbackDelay = reissueFallbackDelay {
    _gatewaySubscription = _gateway.events.listen(_onGatewayEvent);
  }

  /// How long a session Discord ended waits for the gateway to re-issue its
  /// credentials before forcing the issue itself. A seam for the tests; the
  /// production wait is two seconds.
  final Duration _reissueFallbackDelay;

  final DiscordVoiceStateGateway _gateway;
  final DiscordCallGateway? _callGateway;

  /// Where the call's sockets come from, and the stream plane's too.
  final DiscordVoiceSocketFactory _socketFactory;
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

  /// The flags each session was last announced with.
  ///
  /// Re-announcing a channel has to repeat them: opcode 4 is a whole-state
  /// frame, so sending it with the defaults would quietly unmute somebody who
  /// muted themselves — during a reconnect, when they are least likely to
  /// notice.
  final Map<VoiceSessionKey, ({bool mute, bool deaf, bool video})> _lastFlags =
      {};
  final Set<VoiceSessionKey> _pingedSessions = <VoiceSessionKey>{};
  final Map<VoiceSessionKey, int> _generations = {};
  final Map<VoiceSessionKey, DiscordVoiceClient> _clients = {};

  /// The client start running for each session. The next one waits for it.
  final Map<VoiceSessionKey, Future<void>> _clientStarts = {};

  /// What each session's client last reported, so a join into a channel this
  /// service already wants can tell a live connection from a dead one.
  final Map<VoiceSessionKey, VoiceConnectionStatus> _lastStatuses = {};

  /// The timers that escalate a stalled credential re-issue, one per session.
  final Map<VoiceSessionKey, Timer> _reissueTimers = {};

  /// How many leave-and-rejoin cycles a session has forced without reaching
  /// a ready transport. The count is what keeps a server that refuses every
  /// fresh pair from turning the recovery into a loop.
  final Map<VoiceSessionKey, int> _forcedReissues = {};
  static const _maxForcedReissues = 3;

  /// The newest credentials each session was handed a client for.
  final Map<VoiceSessionKey, VoiceServerCredentials> _latestCredentials = {};

  /// The credentials of the client whose transport last reached ready.
  final Map<VoiceSessionKey, VoiceServerCredentials> _readyCredentials = {};

  /// Sessions Discord moved to another channel whose connection has not
  /// settled there yet. While one dials its new connection, the room is
  /// reconnecting rather than joining for the first time.
  final Set<VoiceSessionKey> _moving = {};

  /// The wait after a move for the rest of Discord's move: new credentials,
  /// and a close of the old socket. A close in this wait is part of the move,
  /// so it does not start the opcode 5 recovery.
  final Map<VoiceSessionKey, Timer> _moveTimers = {};

  /// The channels each guild session asked for with opcode 4 that Discord
  /// has not answered yet, oldest first. Discord answers them in order, so a
  /// self voice state naming one of them is an echo, not a move.
  final Map<VoiceSessionKey, List<String?>> _unansweredRequests = {};
  VoiceConnectionStatus _currentStatus = VoiceConnectionStatus.disconnected;
  VoiceTransportSession? _currentSession;
  final Map<VoiceSessionKey, StreamSubscription<VoiceSignalingEvent>>
  _clientSubscriptions = {};
  final Map<VoiceSessionKey, StreamSubscription<VoiceRemoteOpusFrame>>
  _audioSubscriptions = {};
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
  String? _currentUserId;
  String? _currentSessionId;
  VoiceSessionKey? _activeSession;
  bool _closed = false;

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _remoteAudio.stream;

  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  /// The construction site both planes dial through.
  ///
  /// A stream socket has to offer the same DAVE version the call did, and
  /// the version lives behind the factory this service was built with. The
  /// stream plane reaches it the same way it reaches [streamIdentity]:
  /// through the call, because that is where the account's DAVE state is.
  DiscordVoiceSocketFactory get socketFactory => _socketFactory;

  /// What a second connection of this session identifies with.
  ///
  /// Go Live runs on its own socket but not on its own session: it identifies
  /// with the same session id voice did. That id only ever arrives on the self
  /// voice state, so it is kept here rather than asked for again.
  ({String sessionId, String userId})? get streamIdentity {
    // The one the voice state carried, which is the session the call itself
    // identified with. The gateway's own is a different value on a desktop
    // session, and a stream connection offering it is closed with
    // `sessionInvalid`.
    final sessionId = _currentSessionId ?? _gateway.sessionId;
    final userId = _currentUserId;
    if (sessionId == null || userId == null) return null;
    // The two sources, by their last four characters: if they differ, which
    // one a stream connection is given is the difference between a stream
    // that opens and `sessionInvalid`.
    AppLog.warning(
      'stream',
      'identity voice=…${_tail(_currentSessionId)} '
          'gateway=…${_tail(_gateway.sessionId)}',
    );
    return (sessionId: sessionId, userId: userId);
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
      // Joining the channel this session already wants is a flags update on a
      // live connection. On a dead one the identical frame changes nothing
      // server-side, Discord answers it with silence, and the only way out is
      // the leave-and-rejoin cycle below.
      if (_isStuck(key)) {
        // Stored first: the cycle repeats what was last asked for, and this
        // press is the newest choice.
        _lastFlags[key] = (mute: selfMute, deaf: selfDeaf, video: selfVideo);
        _forcedReissues.remove(key);
        _pingedSessions.add(key);
        _forceReissue(key);
        return;
      }
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
    _forcedReissues.remove(key);
    _endMove(key);
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
    _reissueTimers.remove(key)?.cancel();
    _forcedReissues.remove(key);
    _lastStatuses.remove(key);
    _pingedSessions.remove(key);
    _endMove(key);
    _latestCredentials.remove(key);
    _readyCredentials.remove(key);
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
    if (channelId == null) {
      _lastFlags.remove(key);
    } else {
      _lastFlags[key] = (mute: selfMute, deaf: selfDeaf, video: selfVideo);
    }
    final guildId = key.guildId;
    if (guildId != null) {
      (_unansweredRequests[key] ??= []).add(channelId);
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

  /// Whether [channelId] is Discord's answer to one of this client's own
  /// requests. That request and the older ones count as answered.
  bool _answersOwnRequest(VoiceSessionKey key, String? channelId) {
    final unanswered = _unansweredRequests[key];
    final index = unanswered?.indexOf(channelId) ?? -1;
    if (index < 0) return false;
    unanswered!.removeRange(0, index + 1);
    return true;
  }

  /// Both rosters' seats in one map, kept while neither roster changes:
  /// the sidebars key their caches on its identity.
  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel {
    final guilds = _roster.seatedByChannel;
    final calls = _callRoster.seatedByChannel;
    if (!identical(guilds, _mergedGuildSeats) ||
        !identical(calls, _mergedCallSeats)) {
      _mergedGuildSeats = guilds;
      _mergedCallSeats = calls;
      _seatedByChannel = {...guilds, ...calls};
    }
    return _seatedByChannel;
  }

  Map<String, List<VoiceParticipantStateEvent>>? _mergedGuildSeats;
  Map<String, List<VoiceParticipantStateEvent>>? _mergedCallSeats;
  Map<String, List<VoiceParticipantStateEvent>> _seatedByChannel = const {};

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
    final currentUserId = _currentUserId;
    // Every self voice state carries the session a stream connection has to
    // identify with, and it is reissued more often than credentials are
    // rebuilt: the assembler only produces those when a server update
    // arrives too. Holding the one from the first join is how a stream
    // ended up offering a session Discord had already replaced.
    if (currentUserId != null &&
        event.name == 'VOICE_STATE_UPDATE' &&
        event.data['user_id'] == currentUserId) {
      AppLog.warning(
        'voice.creds',
        'self VOICE_STATE_UPDATE fields: ${event.data.keys.join(', ')}',
      );
      final sessionId = event.data['session_id'];
      if (sessionId is String && sessionId.isNotEmpty) {
        _currentSessionId = sessionId;
      }
      // Before the seat itself is announced: the room has to be in the new
      // channel by then, or the account's own seat reads as somebody leaving.
      _followSelfState(event.data);
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
    if (currentUserId == null) return;
    // Which fields the credentials frames carry is the whole question when a
    // connection built from them is refused, and only the names matter: the
    // values are somebody's voice session.
    if (event.name == 'VOICE_SERVER_UPDATE') {
      AppLog.warning(
        'voice.creds',
        'VOICE_SERVER_UPDATE fields: ${event.data.keys.join(', ')}',
      );
    }
    final credentials = _assembler.accept(
      eventName: event.name,
      data: event.data,
      currentUserId: currentUserId,
    );
    if (credentials == null) return;
    _currentSessionId = credentials.sessionId;
    final key = credentials.sessionKey;
    if (_desiredChannels[key] != credentials.channelId) return;
    // A move on the same voice server: the connection stays.
    if (_moving.contains(key) && _isLiveOn(credentials)) {
      _endMove(key);
      return;
    }
    _queueVoiceClient(credentials);
  }

  /// Follows a self voice state that no request of this client explains: a
  /// moderator moved the account, or disconnected it when the channel is
  /// null. The move wins over a reconnect in flight.
  void _followSelfState(Map<String, Object?> data) {
    final guildId = data['guild_id'];
    if (guildId is! String) return;
    final key = VoiceSessionKey.guild(guildId);
    final wanted = _desiredChannels[key];
    final channel = data['channel_id'];
    final channelId = channel is String && channel.isNotEmpty ? channel : null;
    if (_answersOwnRequest(key, channelId) ||
        wanted == null ||
        channelId == wanted) {
      return;
    }
    // Discord has the account elsewhere now, so an answer to an older
    // request would be a move too.
    _unansweredRequests.remove(key);
    _reissueTimers.remove(key)?.cancel();
    _forcedReissues.remove(key);
    final wasRecovering = _pingedSessions.remove(key);
    _endMove(key);
    if (channelId == null) {
      // Discord already has the account out. The room leaves the way a
      // person's own Leave does, and nothing here rejoins in the meantime.
      _desiredChannels.remove(key);
    } else {
      _desiredChannels[key] = channelId;
      _moving.add(key);
      _moveTimers[key] = Timer(_reissueFallbackDelay, () => _moveSettled(key));
      if (wasRecovering) {
        final flags = _lastFlags[key];
        _sendVoiceState(
          key,
          channelId,
          selfMute: flags?.mute ?? false,
          selfDeaf: flags?.deaf ?? false,
          selfVideo: flags?.video ?? false,
        );
      }
      _reaimCredentials(key, channelId);
    }
    _emit(VoiceMovedToChannelEvent(guildId: guildId, channelId: channelId));
  }

  /// Credentials that came in just before the move, and that no connection
  /// has used yet, are the ones Discord issued for the new channel. Without
  /// this the client queued for them gives way to the move, and nothing
  /// dials at all.
  void _reaimCredentials(VoiceSessionKey key, String channelId) {
    final latest = _latestCredentials[key];
    if (latest == null ||
        latest.channelId == channelId ||
        identical(latest, _readyCredentials[key])) {
      return;
    }
    _queueVoiceClient(latest.inChannel(channelId));
  }

  /// Whether [credentials] are the ones the session's working connection
  /// already runs on.
  bool _isLiveOn(VoiceServerCredentials credentials) {
    final key = credentials.sessionKey;
    final live = _readyCredentials[key];
    return live != null &&
        identical(live, _latestCredentials[key]) &&
        _lastStatuses[key] == VoiceConnectionStatus.ready &&
        live.endpoint == credentials.endpoint &&
        live.token == credentials.token;
  }

  /// The wait after a move ran out. A socket Discord closed in it, with no
  /// credentials to rebuild from, is recovered the usual way now.
  void _moveSettled(VoiceSessionKey key) {
    _moveTimers.remove(key);
    if (_lastStatuses[key] == VoiceConnectionStatus.reconnecting &&
        !_pingedSessions.contains(key)) {
      _recover(key);
    }
  }

  void _endMove(VoiceSessionKey key) {
    _moving.remove(key);
    _moveTimers.remove(key)?.cancel();
  }

  /// What the room is told of [event]: while a moved session dials its new
  /// connection, the room is reconnecting, not joining for the first time.
  VoiceSignalingEvent _shownDuringMove(
    VoiceSessionKey key,
    VoiceSignalingEvent event,
  ) => switch (event) {
    VoiceSignalingStatusEvent(
      status: VoiceConnectionStatus.connecting ||
          VoiceConnectionStatus.discovering ||
          VoiceConnectionStatus.negotiating,
      :final error,
    )
        when _moving.contains(key) =>
      VoiceSignalingStatusEvent(
        VoiceConnectionStatus.reconnecting,
        error: error,
      ),
    _ => event,
  };

  /// Pokes the main gateway when a voice socket drops but intends to come back.
  ///
  /// R08: the desktop client answers a will-reconnect disconnect with opcode 5
  /// `VOICE_SERVER_PING`, which is how the server learns to re-issue a
  /// `VOICE_SERVER_UPDATE` for a session it still believes is live. A failing
  /// voice socket can report `reconnecting` repeatedly, so the ping fires on
  /// the transition into that state and not on every repeat, and the
  /// leave-and-rejoin escalation behind it (`_forceReissue`) is capped: left
  /// unguarded either one turns a broken voice connection into a flood on the
  /// main gateway, which is the socket carrying every message.
  @override
  VoiceConnectionStatus get currentStatus => _currentStatus;

  @override
  VoiceTransportSession? get currentSession => _currentSession;

  static String _tail(String? value) => value == null || value.length <= 4
      ? '?'
      : value.substring(value.length - 4);

  void _onClientEvent(
    VoiceServerCredentials credentials,
    VoiceSignalingEvent event,
  ) {
    final key = credentials.sessionKey;
    final shown = _shownDuringMove(key, event);
    // Only the session being listened to speaks for the client's state: a
    // second connection winding down must not report the first as gone.
    if (key == _activeSession) {
      if (shown is VoiceSignalingStatusEvent) _currentStatus = shown.status;
      if (event is VoiceTransportReadyEvent) _currentSession = event.session;
    }
    if (event is VoiceSignalingStatusEvent) {
      _lastStatuses[key] = event.status;
      final wasReconnecting = _pingedSessions.contains(key);
      final isReconnecting = event.status == VoiceConnectionStatus.reconnecting;
      if (isReconnecting && !wasReconnecting) {
        // A close during a move is Discord ending the old socket. The move's
        // own credentials rebuild it, and [_moveSettled] covers them not
        // coming.
        if (!_moveTimers.containsKey(key)) _recover(key);
      } else if (!isReconnecting) {
        _pingedSessions.remove(key);
      }
      if (event.status == VoiceConnectionStatus.failure ||
          event.status == VoiceConnectionStatus.disconnected) {
        _moving.remove(key);
      }
    }
    // A transport that reached ready settles every forced cycle that led to
    // it, and any move; the next time one is needed, the count starts from
    // zero.
    if (event is VoiceTransportReadyEvent) {
      _forcedReissues.remove(key);
      _readyCredentials[key] = credentials;
      _moving.remove(key);
    }
    _emit(shown);
  }

  /// Pings the voice server and announces the channel again, which is how a
  /// session Discord ended asks for fresh credentials.
  void _recover(VoiceSessionKey key) {
    final channelId = _desiredChannels[key];
    final userId = _currentUserId;
    final sessionId = _currentSessionId ?? _gateway.sessionId;
    if (channelId == null || userId == null || sessionId == null) return;
    _pingedSessions.add(key);
    _gateway.pingVoiceServer();
    // And the voice state is sent again. The ping asks the server to
    // re-issue what it already believes it has handed out; re-announcing
    // the channel is what makes it hand out a *new* one. Without this a
    // client holding credentials from a replaced session waited for an
    // update that never came, and the room went from reconnecting
    // straight to disconnected while Discord still had the account in
    // the channel.
    // The identity halves are seeded rather than dropped: a ping that
    // is answered with a lone server update still completes against
    // them, and a stale token or endpoint can no more complete the
    // pairing than it could before.
    _assembler.remember(
      key: key,
      channelId: channelId,
      userId: userId,
      sessionId: sessionId,
    );
    _generations[key] = (_generations[key] ?? 0) + 1;
    final flags = _lastFlags[key];
    _sendVoiceState(
      key,
      channelId,
      selfMute: flags?.mute ?? false,
      selfDeaf: flags?.deaf ?? false,
      selfVideo: flags?.video ?? false,
    );
    _scheduleReissueFallback(key);
  }

  /// Whether the session's connection is one a join into the same channel
  /// has to revive rather than re-announce. A status of null means no client
  /// has reported anything yet: the first pairing is still in flight.
  ///
  /// `reconnecting` is not stuck. The client is still working, and the wait in
  /// [_scheduleReissueFallback] already covers it failing to come back: a mute
  /// pressed meanwhile must not make the room see this account leave and
  /// return.
  bool _isStuck(VoiceSessionKey key) => switch (_lastStatuses[key]) {
    VoiceConnectionStatus.failure || VoiceConnectionStatus.disconnected => true,
    _ => false,
  };

  /// Waits for the gateway to re-issue the session's credentials, then makes
  /// the re-issue happen if nothing arrived.
  ///
  /// The ping and the re-announcement carry no state change, and Discord
  /// answers a voice state that changes nothing with silence, which is how a
  /// refused identify used to sit in `reconnecting` until somebody rejoined
  /// by hand.
  void _scheduleReissueFallback(VoiceSessionKey key) {
    _reissueTimers.remove(key)?.cancel();
    _reissueTimers[key] = Timer(_reissueFallbackDelay, () {
      _reissueTimers.remove(key);
      // Fresh credentials landed on the way and a new client took over.
      if (!_pingedSessions.contains(key)) return;
      _forceReissue(key);
    });
  }

  /// Leaves the channel and rejoins it, which is the one ask Discord always
  /// answers with a fresh `VOICE_STATE_UPDATE` and `VOICE_SERVER_UPDATE`
  /// pair: both halves of the frame change, so nothing is a no-op.
  void _forceReissue(VoiceSessionKey key) {
    final channelId = _desiredChannels[key];
    if (channelId == null) return;
    final forced = (_forcedReissues[key] ?? 0) + 1;
    _forcedReissues[key] = forced;
    if (forced > _maxForcedReissues) {
      _pingedSessions.remove(key);
      _emit(
        VoiceSignalingStatusEvent(
          VoiceConnectionStatus.failure,
          error: StateError(
            'Discord refused $_maxForcedReissues fresh voice sessions in a row',
          ),
        ),
      );
      return;
    }
    final flags = _lastFlags[key];
    _sendVoiceState(key, null);
    _sendVoiceState(
      key,
      channelId,
      selfMute: flags?.mute ?? false,
      selfDeaf: flags?.deaf ?? false,
      selfVideo: flags?.video ?? false,
    );
    // The cycle is answered with a new pair or with nothing; both are waited
    // on, and the cap decides when waiting stops.
    _scheduleReissueFallback(key);
  }

  /// Queues the client for [credentials] behind any start running for its
  /// session.
  ///
  /// Two arrivals in one batch would otherwise overlap. The second finds the
  /// first still closing the old client, so both go on to build one. The map
  /// holds only one of them, and the other keeps playing and reporting with
  /// nothing left to close it.
  ///
  /// The newest credentials take the generation, so a start still waiting
  /// gives way to them instead of dialling a client only to close it.
  void _queueVoiceClient(VoiceServerCredentials credentials) {
    final key = credentials.sessionKey;
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    _latestCredentials[key] = credentials;
    final queued = _clientStarts[key] ?? Future<void>.value();
    final start = queued.then(
      (_) => _startVoiceClient(credentials, generation),
    );
    _clientStarts[key] = start;
    unawaited(
      start.whenComplete(() {
        if (identical(_clientStarts[key], start)) _clientStarts.remove(key);
      }),
    );
  }

  Future<void> _startVoiceClient(
    VoiceServerCredentials credentials,
    int generation,
  ) async {
    final key = credentials.sessionKey;
    try {
      await _closeClient(key);
      if (_closed ||
          generation != _generations[key] ||
          _desiredChannels[key] != credentials.channelId) {
        return;
      }
      // Fresh credentials are the recovery's answer: the fallback that would
      // force another cycle stands down.
      _reissueTimers.remove(key)?.cancel();
      final client = _socketFactory.callSocket(credentials);
      _clients[key] = client;
      _clientSubscriptions[key] = client.events.listen(
        (event) => _onClientEvent(credentials, event),
      );
      if (client case final VoiceAudioTransport audioTransport) {
        _audioSubscriptions[key] = audioTransport.remoteAudio.listen(
          _emitRemoteAudio,
          onError: _remoteAudio.addError,
        );
      }
      _emit(VoiceCredentialsReadyEvent(credentials));
      // Not awaited: a slow dial must not hold up newer credentials. Closing
      // the client ends the dial.
      unawaited(_connectVoiceClient(key, client));
    } on Object catch (error) {
      // A throw must not reach the queue, or every later start is lost.
      if (generation != _generations[key]) return;
      _emit(
        VoiceSignalingStatusEvent(VoiceConnectionStatus.failure, error: error),
      );
    }
  }

  Future<void> _connectVoiceClient(
    VoiceSessionKey key,
    DiscordVoiceClient client,
  ) async {
    try {
      await client.connect();
    } on Object catch (error) {
      // A client that was replaced or left no longer speaks for the session.
      if (!identical(_clients[key], client)) return;
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

  /// The connection behind the session currently joined, if any.
  DiscordVoiceClient? get _activeClient {
    final session = _activeSession;
    return session == null ? null : _clients[session];
  }

  /// Everybody else's cameras on the session currently joined.
  ///
  /// Rebuilt on every join rather than held: the session is a different socket
  /// with different SSRCs, and a subscriber left on the old one would draw a
  /// room nobody is in.
  Stream<(String, DiscordRtpFrame)> get remoteVideo {
    final client = _activeClient;
    if (client == null) return const Stream<(String, DiscordRtpFrame)>.empty();
    return client.videoPackets;
  }

  /// The video plane of the session currently joined, or null when there is
  /// no session to carry one.
  VoiceVideoTransport? get activeVideoTransport => _activeClient;

  /// Encrypts and sends one video RTP frame on the active session.
  ///
  /// The same socket and the same cipher the audio uses: a camera is another
  /// SSRC on the connection that is already open, not a second connection.
  int sendVideoFrame(DiscordRtpFrame frame) {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Discord voice transport is not ready');
    }
    return client.sendVideoFrame(frame);
  }

  /// Encrypts one whole camera picture for the room's group on the active
  /// session, before the caller packetises it.
  ///
  /// Looked up per call rather than bound once: a reconnect replaces the
  /// client, and a closure over the old one would encrypt pictures with a
  /// key from a session nobody holds anymore.
  Uint8List encryptVideoGroupFrame(Uint8List frame) {
    final client = _activeClient;
    final audioSsrc = client?.audioSsrc;
    if (client == null || audioSsrc == null) {
      throw StateError('Discord voice transport is not ready');
    }
    return client.encryptVideoForGroup(
      ssrc: DiscordVoiceGatewayProtocol.videoSsrcFor(audioSsrc),
      frame: frame,
    );
  }

  /// Decrypts one whole camera picture for the room's group on the active
  /// session, after the caller has reassembled it from its packets.
  ///
  /// Looked up per call rather than bound once, for the same reason as
  /// [encryptVideoGroupFrame]: a reconnect replaces the client, and a closure
  /// over the old one would try to decrypt with a key from a session nobody
  /// holds anymore.
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  }) {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Discord voice transport is not ready');
    }
    return client.decryptVideoGroupFrame(userId: userId, picture: picture);
  }

  /// Asks whoever sends pictures on [mediaSsrc] for a keyframe (RFC 4585),
  /// on the session currently joined. Nothing to ask when there is none.
  void sendPictureLoss({required int mediaSsrc}) =>
      _activeClient?.sendPictureLoss(mediaSsrc: mediaSsrc);

  @override
  void sendOpusFrame(Uint8List opusFrame) {
    final client = _activeClient;
    if (client case final VoiceAudioTransport audioTransport) {
      audioTransport.sendOpusFrame(opusFrame);
      return;
    }
    throw StateError('Discord voice media transport is not ready');
  }

  /// Nothing to keep time with between sessions: the next one starts its
  /// own clock.
  @override
  void skipOpusFrame() {
    if (_activeClient case final VoiceAudioTransport audioTransport) {
      audioTransport.skipOpusFrame();
    }
  }

  @override
  Future<void> finishSpeaking() async {
    final client = _activeClient;
    if (client case final VoiceAudioTransport audioTransport) {
      await audioTransport.finishSpeaking();
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
    for (final timer in [..._reissueTimers.values, ..._moveTimers.values]) {
      timer.cancel();
    }
    _reissueTimers.clear();
    _moveTimers.clear();
    for (final key in _clients.keys.toList(growable: false)) {
      await _closeClient(key);
    }
    _assembler.clearAll();
    _roster.clearAll();
    _callRoster.clearAll();
    await _remoteAudio.close();
    await _events.close();
  }
}
