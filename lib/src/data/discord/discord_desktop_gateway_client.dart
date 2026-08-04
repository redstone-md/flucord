import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../zstd/zstd_codec.dart';
import 'discord_desktop_bootstrap.dart';
import 'discord_desktop_gateway_protocol.dart';
import 'discord_desktop_profile.dart';
import 'discord_desktop_voice_frames.dart';
import 'discord_desktop_websocket.dart';
import 'discord_gateway_client.dart';
import 'discord_gateway_transport_codec.dart';
import 'discord_guild_subscriptions.dart';
import 'discord_rest_client.dart';

export 'discord_desktop_bootstrap.dart' show DiscordDesktopWorkspaceSnapshot;

final class DiscordDesktopGatewayClient
    implements DiscordChatGateway, DiscordCallGateway {
  DiscordDesktopGatewayClient({
    required String authorization,
    required Map<String, Object?> properties,
    this.profile = DiscordDesktopProtocolProfile.installedStable20260725,
    this._socketConnector = const PlatformDiscordDesktopWebSocketConnector(),
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

  DiscordDesktopWebSocket? _socket;
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
    if (_closing) return;
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
    try {
      _socket = await _socketConnector.connect(uri);
      _socket!.messages.listen(
        _accept,
        onDone: _onDone,
        onError: _onSocketError,
        cancelOnError: true,
      );
    } on Object catch (error, stackTrace) {
      _lastBootstrapError = error;
      _logBootstrapFailure('websocket-upgrade', error, stackTrace);
      _scheduleReconnect(reason: 'websocket upgrade failed: $error');
    }
  }

  void _accept(Object? raw) {
    try {
      final payloads = _codec.decode(raw);
      if (payloads.isEmpty) {
        if (_bootstrapCompleter?.isCompleted == false) {
          developer.log(
            'Discord Gateway bootstrap ignored a ${raw.runtimeType} frame.',
            name: 'flucord.discord.gateway',
            level: 900,
          );
        }
        return;
      }
      for (final payload in payloads) {
        _acceptPayload(payload);
      }
    } on ZstdException catch (error, stackTrace) {
      // A decompression failure is not recoverable in place. The stream is one
      // continuous context, so once it desynchronises every later frame is
      // garbage decoded against poisoned history — and logging and returning
      // would leave the socket looking healthy while delivering nothing.
      // Reconnecting is the only correct response; _open resets the decoder.
      _lastBootstrapError = error;
      _logBootstrapFailure('transport-compression', error, stackTrace);
      _scheduleReconnect(
        immediate: true,
        reason: 'transport compression failed: $error',
      );
      return;
    } on FormatException catch (error, stackTrace) {
      _lastBootstrapError = error;
      _logBootstrapFailure(
        'frame-${_codec.framing.encoding}',
        error,
        stackTrace,
      );
      return;
    } on TypeError catch (error, stackTrace) {
      _lastBootstrapError = error;
      _logBootstrapFailure('frame-shape', error, stackTrace);
      return;
    }
  }

  /// The gateway session, or `null` before READY.
  @override
  String? get sessionId => _protocol.sessionId;

  /// Opcode 18. `type` is `guild` or `call`, matching how the stream key is
  /// composed, and the region is a preference Discord may ignore.
  void sendStreamCreate({
    required String type,
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamCreate, {
      'type': type,
      'channel_id': channelId,
      'guild_id': ?guildId,
      'preferred_region': ?preferredRegion,
    }),
  );

  /// Opcode 19.
  void sendStreamDelete(String streamKey) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamDelete, {
      'stream_key': streamKey,
    }),
  );

  /// Opcode 20.
  void sendStreamWatch(String streamKey) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamWatch, {
      'stream_key': streamKey,
    }),
  );

  /// Opcode 21.
  void sendStreamPing(String streamKey) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamPing, {
      'stream_key': streamKey,
    }),
  );

  /// Opcode 22.
  void sendStreamSetPaused(String streamKey, {required bool paused}) => _send(
    DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.streamSetPaused, {
      'stream_key': streamKey,
      'paused': paused,
    }),
  );

  void _acceptPayload(Map<String, Object?> payload) {
    if (_bootstrapCompleter?.isCompleted == false) {
      developer.log(
        'Discord Gateway bootstrap frame: op=${payload['op']}, '
        'event=${payload['t'] ?? '-'}',
        name: 'flucord.discord.gateway',
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
          _diagnose(action.name.toLowerCase());
        }
        if (action.name == 'READY') {
          _emitStatus(DiscordGatewayStatus.connected);
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
    _diagnose(
      'heartbeat',
      action is DiscordDesktopGatewayReconnect ? 'unanswered' : 'sent',
    );
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
      developer.log(
        'Gateway send failed, reconnecting: ${_diagnosticFor(error)}',
        name: 'flucord.discord.gateway',
        level: 900,
      );
      unawaited(socket.close());
      _socket = null;
      _scheduleReconnect(immediate: true, reason: 'send failed');
    }
  }

  void _onDone() {
    final code = _socket?.closeCode;
    _lastBootstrapCloseCode = code;
    if (_bootstrapCompleter?.isCompleted == false) {
      developer.log(
        'Discord Gateway closed during bootstrap (code=${code ?? 'unknown'}).',
        name: 'flucord.discord.gateway',
        level: 900,
      );
    }
    if (code == 4004) {
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
    // The code the *closing* socket carried, read before anything replaces
    // it, and how long since a heartbeat went out — a socket that dies a
    // moment after one usually died because of it.
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
    developer.log(
      'Discord Gateway bootstrap failed at $stage: ${_diagnosticFor(error)}',
      name: 'flucord.discord.gateway',
      level: 1000,
      stackTrace: stackTrace,
    );
  }

  static String _diagnosticFor(Object error) => switch (error) {
    DiscordApiException() => 'HTTP ${error.statusCode}: ${error.message}',
    _ => '${error.runtimeType}: $error',
  };

  /// Says what the session just did, where it can be read.
  ///
  /// The voice sockets identify with this session's id, so its reconnects are
  /// the first thing to check when Discord starts answering voice with 4022 —
  /// "session expired" downstream is this session having been replaced.
  void _diagnose(String what, [Object? detail]) {
    final line = 'flucord.gateway $what${detail == null ? '' : ': $detail'}';
    developer.log(line, name: 'flucord.discord.gateway', level: 900);
    if (kDebugMode) stdout.writeln(line);
  }

  void _scheduleReconnect({bool immediate = false, String reason = 'unknown'}) {
    if (_closing || _reconnectTimer?.isActive == true) return;
    _diagnose('reconnecting', reason);
    _heartbeatTimer?.cancel();
    _initialHeartbeatTimer?.cancel();
    _emitStatus(DiscordGatewayStatus.reconnecting);
    unawaited(_socket?.close());
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
    await _socket?.close();
    _voiceFrames.clear();
    _subscriptions.clear();
    _emitStatus(DiscordGatewayStatus.offline);
    await _events.close();
  }
}
