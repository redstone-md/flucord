import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../zstd/zstd_codec.dart';
import 'discord_desktop_bootstrap.dart';
import 'discord_desktop_gateway_protocol.dart';
import 'discord_desktop_profile.dart';
import 'discord_desktop_voice_frames.dart';
import 'discord_desktop_websocket.dart';
import 'discord_gateway_client.dart';
import 'discord_gateway_rules.dart';
import 'discord_gateway_socket_queue.dart';
import 'discord_gateway_transport_codec.dart';
import 'discord_go_live_service.dart';
import 'discord_guild_subscriptions.dart';
import 'discord_rest_client.dart';
import 'discord_role_dispatch.dart';
import '../../app_log.dart';

export 'discord_desktop_bootstrap.dart' show DiscordDesktopWorkspaceSnapshot;

final class DiscordDesktopGatewayClient
    implements DiscordChatGateway, DiscordCallGateway, DiscordGoLiveGateway {
  DiscordDesktopGatewayClient({
    required String authorization,
    required Map<String, Object?> properties,
    this.profile = DiscordDesktopProtocolProfile.installedStable20260725,
    this._socketConnector = const PlatformDiscordDesktopWebSocketConnector(
      decodeJsonInWorker: true,
    ),
  }) : _protocol = DiscordDesktopGatewayProtocol(
         token: authorization,
         properties: properties,
         profile: profile,
       ),
       _codec = DiscordGatewayTransportCodec.forProfile(
         encoding: profile.gatewayEncoding,
         compression: profile.negotiatedCompression,
       );

  final DiscordDesktopProtocolProfile profile;
  final DiscordDesktopGatewayProtocol _protocol;
  final DiscordGatewayTransportCodec _codec;
  final DiscordDesktopWebSocketConnector _socketConnector;
  final DiscordGuildSubscriptions _subscriptions = DiscordGuildSubscriptions();
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();
  final Random _random = Random();
  final DiscordDesktopVoiceFrames _voiceFrames = DiscordDesktopVoiceFrames();
  final DiscordDesktopBootstrap _bootstrap = DiscordDesktopBootstrap();

  /// The one socket this client reads from and writes to. A socket stops being
  /// this the moment a reconnect or a close gives up on it, so what it still
  /// reports from then on means nothing.
  DiscordDesktopWebSocket? _socket;
  bool _dialing = false;
  Timer? _heartbeatTimer;
  Timer? _initialHeartbeatTimer;
  Timer? _reconnectTimer;
  DateTime? _lastHeartbeatSentAt;
  Timer? _bootstrapTimer;
  Completer<DiscordDesktopWorkspaceSnapshot>? _bootstrapCompleter;
  Uri? _gatewayUri;
  bool _closing = false;
  Object? _lastBootstrapError;
  int? _lastBootstrapCloseCode;

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  /// Whether the socket has a session the server will accept frames for.
  ///
  /// R07 gates the presence sender on exactly this: a frame sent before
  /// IDENTIFY has been answered is discarded by the server, and the client
  /// would then believe it had broadcast a status it never did.
  bool get isSessionEstablished =>
      _protocol.state == DiscordDesktopGatewayState.established &&
      _socket?.isOpen == true;

  /// Sends opcode 3 and remembers the payload for the next IDENTIFY.
  void updatePresence(Map<String, Object?> payload) =>
      _send(_protocol.presenceUpdate(payload));

  /// Lets the session's caches answer for `client_state` on each IDENTIFY.
  void useClientStateProvider(Map<String, Object?> Function() provider) =>
      _protocol.clientStateProvider = provider;

  @override
  Future<void> connect(String gatewayUrl) async {
    _gatewayUri = Uri.parse(gatewayUrl);
    _closing = false;
    await _open();
  }

  Future<DiscordDesktopWorkspaceSnapshot> connectAndReadWorkspace(
    String gatewayUrl,
  ) async {
    _bootstrapCompleter = Completer<DiscordDesktopWorkspaceSnapshot>();
    _bootstrap.reset();
    _lastBootstrapError = null;
    _lastBootstrapCloseCode = null;
    await connect(gatewayUrl);
    return _bootstrapCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        final snapshot = _bootstrap.snapshot();
        if (snapshot == null) {
          final detail = _lastBootstrapError == null
              ? (_lastBootstrapCloseCode == null
                    ? ''
                    : ' (last close code: $_lastBootstrapCloseCode)')
              : ' (last transport error: '
                    '${_diagnosticFor(_lastBootstrapError!)})';
          throw DiscordApiException(
            statusCode: 504,
            message: 'Discord Gateway bootstrap timed out$detail',
          );
        }
        return snapshot;
      },
    );
  }

  Future<void> _open() async {
    if (_closing || _dialing) return;
    _emitStatus(
      _protocol.canResume
          ? DiscordGatewayStatus.reconnecting
          : DiscordGatewayStatus.connecting,
    );
    final base = _protocol.resumeGatewayUri ?? _gatewayUri;
    if (base == null) return;
    final uri = profile.connectionUri(resumeUri: base);
    // Transport compression is per connection. Carrying a decompressor across a
    // reconnect would resolve matches against the previous session's bytes.
    _codec.reset();
    _dialing = true;
    try {
      final socket = await _socketConnector.connect(uri);
      if (_closing) {
        await socket.close();
        return;
      }
      _listenTo(socket);
    } on Object catch (error, stackTrace) {
      _lastBootstrapError = error;
      _logBootstrapFailure('websocket-upgrade', error, stackTrace);
      _scheduleReconnect(reason: 'websocket upgrade failed: $error');
    } finally {
      _dialing = false;
    }
  }

  /// Makes [socket] the current one. Its callbacks work only while it stays
  /// current: a close handshake can end long after a new socket took over, and
  /// the old socket's done event must not take the new one down with it.
  ///
  /// The stream stays subscribed after that, because the platform needs it read
  /// to finish the close handshake.
  void _listenTo(DiscordDesktopWebSocket socket) {
    _socket = socket;
    bool isCurrent() => identical(socket, _socket);
    final queue = DiscordGatewaySocketQueue();
    void inOrder(FutureOr<void> Function() step) =>
        queue.add(() => isCurrent() ? step() : null);
    socket.messages.listen(
      (raw) => inOrder(() => _accept(raw, isCurrent)),
      onDone: () => inOrder(() => _onDone(socket)),
      onError: (Object error, StackTrace stackTrace) =>
          inOrder(() => _onSocketError(error, stackTrace)),
      cancelOnError: true,
    );
  }

  /// Handles one frame, at once or, for a large one, after a worker decoded it.
  FutureOr<void> _accept(Object? raw, bool Function() isCurrent) {
    try {
      final decoded = _codec.decode(raw);
      if (decoded is Future<List<Map<String, Object?>>>) {
        return _acceptDecoding(raw, decoded, isCurrent);
      }
      _acceptPayloads(raw, decoded);
    } on Object catch (error, stackTrace) {
      _onFrameFailed(error, stackTrace);
    }
  }

  /// A socket can stop being current during the decoding, and then the frame
  /// means nothing, whether or not it was good.
  Future<void> _acceptDecoding(
    Object? raw,
    Future<List<Map<String, Object?>>> decoding,
    bool Function() isCurrent,
  ) async {
    try {
      final payloads = await decoding;
      if (isCurrent()) _acceptPayloads(raw, payloads);
    } on Object catch (error, stackTrace) {
      if (isCurrent()) _onFrameFailed(error, stackTrace);
    }
  }

  void _acceptPayloads(Object? raw, List<Map<String, Object?>> payloads) {
    if (payloads.isEmpty) {
      if (_bootstrapCompleter?.isCompleted == false) {
        AppLog.warning(
          'discord.gateway',
          'Discord Gateway bootstrap ignored a ${raw.runtimeType} frame.',
        );
      }
      return;
    }
    for (final payload in payloads) {
      _acceptPayload(payload);
    }
  }

  void _onFrameFailed(Object error, StackTrace stackTrace) {
    switch (error) {
      case ZstdException():
        // A decompression failure is not recoverable in place. The stream is one
        // continuous context, so once it desynchronises every later frame is
        // garbage decoded against poisoned history, and logging and returning
        // would leave the socket looking healthy while delivering nothing.
        // Reconnecting is the only correct response; _open resets the decoder.
        _lastBootstrapError = error;
        _logBootstrapFailure('transport-compression', error, stackTrace);
        _scheduleReconnect(
          immediate: true,
          reason: 'transport compression failed: $error',
        );
      case FormatException():
        _lastBootstrapError = error;
        _logBootstrapFailure(
          'frame-${_codec.framing.encoding}',
          error,
          stackTrace,
        );
      case TypeError():
        _lastBootstrapError = error;
        _logBootstrapFailure('frame-shape', error, stackTrace);
      case IsolateSpawnException() || RemoteError():
        // The worker itself failed, so the frame was never read. Its sequence
        // number was not counted either, so a resume brings it back.
        _lastBootstrapError = error;
        _logBootstrapFailure('frame-worker', error, stackTrace);
        _scheduleReconnect(reason: 'frame worker failed: $error');
      default:
        Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// The gateway session, or `null` before READY.
  @override
  String? get sessionId => _protocol.sessionId;

  /// The account this session is signed in as, or `null` before READY.
  @override
  String? get currentUserId => _protocol.currentUserId;

  /// The hydration state as the opening dispatches currently describe it.
  ///
  /// `null` before the first READY. A READY that lands after the first one,
  /// which is what a reconnect that could not resume produces, keeps this
  /// current, and the in-place rehydration reads it from there.
  DiscordDesktopWorkspaceSnapshot? get workspaceSnapshot =>
      _bootstrap.snapshot();

  /// Opcode 18. `type` is `guild` or `call`, matching how the stream key is
  /// composed, and the region is a preference Discord may ignore.
  @override
  void sendStreamCreate({
    required String type,
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamCreate, {
      'type': type,
      'channel_id': channelId,
      'guild_id': guildId,
      // Present and null rather than absent, which is how Discord's own
      // clients send it. A create is answered either way, but the session the
      // answer describes is the one the RTC server will accept.
      'preferred_region': preferredRegion,
    }),
  );

  /// Opcode 19.
  @override
  void sendStreamDelete(String streamKey) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamDelete, {
      'stream_key': streamKey,
    }),
  );

  /// Opcode 20.
  @override
  void sendStreamWatch(String streamKey) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamWatch, {
      'stream_key': streamKey,
    }),
  );

  /// Opcode 21.
  @override
  void sendStreamPing(String streamKey) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamPing, {
      'stream_key': streamKey,
    }),
  );

  /// Opcode 22.
  @override
  void sendStreamSetPaused(String streamKey, {required bool paused}) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamSetPaused, {
      'stream_key': streamKey,
      'paused': paused,
    }),
  );

  void _acceptPayload(Map<String, Object?> payload) {
    if (_bootstrapCompleter?.isCompleted == false) {
      AppLog.info(
        'discord.gateway',
        'Discord Gateway bootstrap frame: op=${payload['op']}, '
            'event=${payload['t'] ?? '-'}',
      );
    }
    for (final action in _protocol.accept(payload)) {
      _apply(action);
    }
    if (payload['op'] == DiscordDesktopGatewayOpcode.hello) {
      _send(_protocol.canResume ? _protocol.resume() : _protocol.identify());
    }
  }

  void _apply(DiscordDesktopGatewayAction action) {
    switch (action) {
      case DiscordDesktopGatewaySend():
        _send(action.frame);
      case DiscordDesktopGatewayScheduleHeartbeat():
        _startHeartbeat(action.interval);
      case DiscordDesktopGatewayReconnect():
        _scheduleReconnect(
          immediate: action.immediate,
          reason: 'the protocol asked for one',
        );
      case DiscordDesktopGatewayDispatch():
        _captureBootstrap(action);
        if (action.name == 'READY' || action.name == 'RESUMED') {
          AppLog.info('discord.gateway', action.name.toLowerCase());
          _emitStatus(DiscordGatewayStatus.connected);
        }
        if (action.name == 'READY') {
          _subscribeReadyGuilds(action.data);
          for (final frame in _voiceFrames.replay) {
            _send(frame);
          }
        }
        if (!_events.isClosed) {
          _events.add(
            DiscordGatewayDispatch(name: action.name, data: action.data),
          );
        }
    }
  }

  void _captureBootstrap(DiscordDesktopGatewayDispatch dispatch) {
    // Hydration is fed unconditionally. The bootstrap completer only decides
    // when the first snapshot is handed back; gating ingestion on it lost every
    // READY_SUPPLEMENTAL that arrived after the snapshot timer had already
    // fired, which dropped `lazy_private_channels` and left the READY user
    // table alive for the rest of the session.
    final delay = switch (dispatch.name) {
      'READY' => () {
        _bootstrap.acceptReady(dispatch.data);
        return const Duration(seconds: 2);
      }(),
      'GUILD_CREATE' => () {
        _bootstrap.acceptGuild(dispatch.data);
        return const Duration(milliseconds: 350);
      }(),
      'READY_SUPPLEMENTAL' => () {
        _bootstrap.acceptSupplemental(dispatch.data);
        return const Duration(milliseconds: 350);
      }(),
      'GUILD_ROLE_CREATE' || 'GUILD_ROLE_UPDATE' || 'GUILD_ROLE_DELETE' => () {
        final change = DiscordRoleDispatch.read(dispatch.name, dispatch.data);
        if (change != null) _bootstrap.acceptRole(change);
        return null;
      }(),
      // A guild in an outage is still the account's, so it keeps its entry.
      'GUILD_DELETE' => () {
        final id = dispatch.data['id'];
        if (id is String && dispatch.data['unavailable'] != true) {
          _bootstrap.removeGuild(id);
        }
        return null;
      }(),
      _ => null,
    };
    if (delay == null || _bootstrapCompleter?.isCompleted != false) return;
    _scheduleBootstrapCompletion(delay);
  }

  void _scheduleBootstrapCompletion(Duration delay) {
    _bootstrapTimer?.cancel();
    _bootstrapTimer = Timer(delay, () {
      final snapshot = _bootstrap.snapshot();
      if (snapshot != null && _bootstrapCompleter?.isCompleted == false) {
        _bootstrapCompleter!.complete(snapshot);
      }
    });
  }

  /// Asks a guild for members whose name starts with [query].
  ///
  /// Discord answers with `GUILD_MEMBERS_CHUNK`. A blank query is not sent:
  /// it would ask for the head of the whole guild, which is a request nobody
  /// meant to make by typing an at-sign.
  void requestGuildMembers({
    required String guildId,
    required String query,
    int limit = 25,
  }) {
    if (guildId.isEmpty || query.trim().isEmpty) return;
    _send(
      _protocol.requestGuildMembers(
        guildId: guildId,
        query: query.trim(),
        limit: limit,
      ),
    );
  }

  /// Opcode 8 by id: asks the guild for exactly these members.
  void requestGuildMembersByIds({
    required String guildId,
    required List<String> userIds,
  }) {
    if (guildId.isEmpty || userIds.isEmpty) return;
    _send(_protocol.requestGuildMembersByIds(guildId, userIds));
  }

  /// Subscribes a channel's member-list row ranges.
  ///
  /// Discord answers with `GUILD_MEMBER_LIST_UPDATE` for the channel's
  /// visibility class. Ranges must be page-aligned and always include the head
  /// page; [DiscordMemberListRanges] produces a conforming set.
  void subscribeMemberRanges({
    required String guildId,
    required String channelId,
    required List<List<int>> ranges,
  }) {
    if (!_subscriptions.setChannelRanges(guildId, channelId, ranges)) return;
    _sendSubscriptions({guildId: _subscriptions.snapshot(guildId)});
  }

  /// Drops a channel's member-list subscription.
  void unsubscribeMemberRanges({
    required String guildId,
    required String channelId,
  }) {
    if (!_subscriptions.removeChannel(guildId, channelId)) return;
    _sendSubscriptions({guildId: _subscriptions.snapshot(guildId)});
  }

  /// Registers the base flags for a guild the session gained after READY.
  ///
  /// Discord pushes live events for a guild only once it is subscribed, and
  /// the subscriptions map is a replace: without this, typing, thread and
  /// member events for a joined server never arrive, because READY named the
  /// guilds it listed and nothing else. Answers whether this is news, which is
  /// false for a guild that was already subscribed.
  bool subscribeGuildEvents(String guildId) {
    if (!_subscriptions.setFlags(guildId)) return false;
    _sendSubscriptions({guildId: _subscriptions.snapshot(guildId)});
    return true;
  }

  /// Forgets a guild the account left, so a reconnect does not resubscribe
  /// to a server the account can no longer open.
  void forgetGuild(String guildId) => _subscriptions.removeGuild(guildId);

  void _subscribeReadyGuilds(Map<String, Object?> ready) {
    final guilds = ready['guilds'];
    if (guilds is! List) return;
    for (final guild in guilds.whereType<Map>()) {
      final id = guild['id'];
      if (id is String) _subscriptions.setFlags(id);
    }
    // A reconnect replays the whole subscription state, because the server
    // keeps none of it across sessions and a resumed socket would otherwise
    // stop delivering member-list and typing events for open channels.
    _sendSubscriptions(_subscriptions.snapshotAll());
  }

  void _sendSubscriptions(Map<String, Map<String, Object?>> subscriptions) {
    if (subscriptions.isEmpty) return;
    for (final frame in _protocol.guildSubscriptionFrames(subscriptions)) {
      _send(frame);
    }
  }

  void _startHeartbeat(Duration interval) {
    _heartbeatTimer?.cancel();
    _initialHeartbeatTimer?.cancel();
    final jitter = Duration(
      milliseconds: (interval.inMilliseconds * _random.nextDouble()).round(),
    );
    _initialHeartbeatTimer = Timer(jitter, () {
      _heartbeat();
      _heartbeatTimer = Timer.periodic(interval, (_) => _heartbeat());
    });
  }

  void _heartbeat() {
    _lastHeartbeatSentAt = DateTime.now();
    final action = _protocol.heartbeatDue();
    // A heartbeat that goes out is routine; only one left unanswered is news.
    if (action is DiscordDesktopGatewayReconnect) {
      _diagnose('heartbeat', 'unanswered');
    }
    _apply(action);
  }

  void _send(DiscordDesktopGatewayFrame frame) {
    final socket = _socket;
    if (socket == null || !socket.isOpen) return;
    final encoded = _codec.encode(frame.toJson());
    try {
      if (encoded is String) {
        socket.send(encoded);
      } else {
        socket.sendBinary(encoded as Uint8List);
      }
    } on Object catch (error) {
      // A socket can close between the check above and the write: the
      // platform reports it as a failed send rather than as a closed socket,
      // and WinHTTP in particular answers 12017 for a connection that went
      // away mid-frame. Left to propagate it killed the isolate's error zone
      // — the session then sat there looking connected while nothing moved.
      AppLog.warning(
        'discord.gateway',
        'Gateway send failed, reconnecting: ${_diagnosticFor(error)}',
      );
      _scheduleReconnect(immediate: true, reason: 'send failed');
    }
  }

  void _onDone(DiscordDesktopWebSocket socket) {
    final code = socket.closeCode;
    _lastBootstrapCloseCode = code;
    if (_bootstrapCompleter?.isCompleted == false) {
      AppLog.warning(
        'discord.gateway',
        'Discord Gateway closed during bootstrap (code=${code ?? 'unknown'}).',
      );
    }
    if (code == DiscordGatewayCloseCodes.authenticationFailed) {
      _emitStatus(DiscordGatewayStatus.offline);
      final completer = _bootstrapCompleter;
      if (completer?.isCompleted == false) {
        completer!.completeError(
          const DiscordApiException(
            statusCode: 401,
            message: 'Discord Gateway rejected the authorization credential',
          ),
        );
      }
      return;
    }
    // How long since a heartbeat went out: a socket that dies a moment after
    // one usually died because of it.
    _scheduleReconnect(
      reason:
          'socket closed (code ${code ?? 'none'}, '
          '${_sinceLastHeartbeat()} since heartbeat)',
    );
  }

  String _sinceLastHeartbeat() {
    final sent = _lastHeartbeatSentAt;
    if (sent == null) return 'no heartbeat yet';
    return '${DateTime.now().difference(sent).inSeconds}s';
  }

  void _onSocketError(Object error, StackTrace stackTrace) {
    _lastBootstrapError = error;
    _logBootstrapFailure('websocket-stream', error, stackTrace);
    _scheduleReconnect(reason: 'socket error: $error');
  }

  void _logBootstrapFailure(String stage, Object error, StackTrace stackTrace) {
    if (_bootstrapCompleter?.isCompleted != false) return;
    AppLog.error(
      'discord.gateway',
      'Discord Gateway bootstrap failed at $stage: ${_diagnosticFor(error)}',
      stackTrace: stackTrace,
    );
  }

  static String _diagnosticFor(Object error) => switch (error) {
    DiscordApiException() => 'HTTP ${error.statusCode}: ${error.message}',
    _ => '${error.runtimeType}: $error',
  };

  /// Records a problem the session ran into and handled.
  ///
  /// The voice sockets identify with this session's id, so its reconnects are
  /// the first thing to check when Discord starts answering voice with
  /// `sessionExpired`, which is this session having been replaced.
  void _diagnose(String what, [Object? detail]) {
    AppLog.warning(
      'discord.gateway',
      '$what${detail == null ? '' : ': $detail'}',
    );
  }

  void _scheduleReconnect({bool immediate = false, String reason = 'unknown'}) {
    if (_closing || _reconnectTimer?.isActive == true) return;
    _diagnose('reconnecting', reason);
    _heartbeatTimer?.cancel();
    _initialHeartbeatTimer?.cancel();
    _emitStatus(DiscordGatewayStatus.reconnecting);
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
    _reconnectTimer = Timer(
      immediate ? Duration.zero : const Duration(seconds: 2),
      _open,
    );
  }

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) => _send(
    _voiceFrames.voiceState(
      sessionKey: guildId,
      guildId: guildId,
      channelId: channelId,
      selfMute: selfMute,
      selfDeaf: selfDeaf,
      selfVideo: selfVideo,
    ),
  );

  /// R08: a DM or group-DM call sends the same opcode 4 with `guild_id: null`.
  ///
  /// The channel is still required when leaving, because the frame that leaves
  /// carries `channel_id: null` and would otherwise name no session at all —
  /// the desired-state map would keep replaying a call the user has hung up.
  @override
  void updateCallVoiceState({
    required String channelId,
    required bool connected,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) => _send(
    _voiceFrames.voiceState(
      sessionKey: channelId,
      guildId: null,
      channelId: connected ? channelId : null,
      selfMute: selfMute,
      selfDeaf: selfDeaf,
      selfVideo: selfVideo,
    ),
  );

  @override
  void connectToCall(String channelId) {
    final frame = _voiceFrames.callConnect(channelId);
    if (frame != null) _send(frame);
  }

  @override
  void pingVoiceServer() => _send(_voiceFrames.voiceServerPing);

  void _emitStatus(DiscordGatewayStatus status) {
    if (!_events.isClosed) _events.add(DiscordGatewayStatusEvent(status));
  }

  @override
  Future<void> close() async {
    _closing = true;
    _reconnectTimer?.cancel();
    _bootstrapTimer?.cancel();
    _heartbeatTimer?.cancel();
    _initialHeartbeatTimer?.cancel();
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _voiceFrames.clear();
    _subscriptions.clear();
    _emitStatus(DiscordGatewayStatus.offline);
    await _events.close();
  }
}
