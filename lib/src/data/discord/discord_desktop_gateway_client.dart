import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'discord_desktop_gateway_protocol.dart';
import 'discord_desktop_profile.dart';
import 'discord_desktop_websocket.dart';
import 'discord_gateway_client.dart';
import 'discord_gateway_framing.dart';
import 'discord_rest_client.dart';

final class DiscordDesktopWorkspaceSnapshot {
  DiscordDesktopWorkspaceSnapshot({
    required Map<String, Object?> currentUser,
    required Iterable<Map<String, Object?>> guilds,
    required Iterable<Map<String, Object?>> directChannels,
    required Map<String, List<Map<String, Object?>>> channelsByGuild,
  }) : currentUser = Map<String, Object?>.unmodifiable(currentUser),
       guilds = List<Map<String, Object?>>.unmodifiable(
         guilds.map(Map<String, Object?>.unmodifiable),
       ),
       directChannels = List<Map<String, Object?>>.unmodifiable(
         directChannels.map(Map<String, Object?>.unmodifiable),
       ),
       channelsByGuild = Map<String, List<Map<String, Object?>>>.unmodifiable({
         for (final entry in channelsByGuild.entries)
           entry.key: List<Map<String, Object?>>.unmodifiable(
             entry.value.map(Map<String, Object?>.unmodifiable),
           ),
       });

  final Map<String, Object?> currentUser;
  final List<Map<String, Object?>> guilds;
  final List<Map<String, Object?>> directChannels;
  final Map<String, List<Map<String, Object?>>> channelsByGuild;
}

final class DiscordDesktopGatewayClient implements DiscordChatGateway {
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
       _framing = DiscordGatewayFraming.forEncoding(profile.gatewayEncoding);

  final DiscordDesktopProtocolProfile profile;
  final DiscordDesktopGatewayProtocol _protocol;
  final DiscordGatewayFraming _framing;
  final DiscordDesktopWebSocketConnector _socketConnector;
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();
  final Random _random = Random();
  final Map<String, Map<String, Object?>> _desiredVoiceStates = {};
  final Map<String, Map<String, Object?>> _bootstrapGuilds = {};
  final Map<String, List<Map<String, Object?>>> _bootstrapChannels = {};

  DiscordDesktopWebSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _initialHeartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _bootstrapTimer;
  Completer<DiscordDesktopWorkspaceSnapshot>? _bootstrapCompleter;
  Map<String, Object?>? _bootstrapUser;
  List<Map<String, Object?>> _bootstrapDirectChannels = const [];
  Uri? _gatewayUri;
  bool _closing = false;
  Object? _lastBootstrapError;
  int? _lastBootstrapCloseCode;

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

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
    _bootstrapGuilds.clear();
    _bootstrapChannels.clear();
    _bootstrapUser = null;
    _bootstrapDirectChannels = const [];
    _lastBootstrapError = null;
    _lastBootstrapCloseCode = null;
    await connect(gatewayUrl);
    return _bootstrapCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        final snapshot = _snapshot();
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
      _scheduleReconnect();
    }
  }

  void _accept(Object? raw) {
    try {
      final payload = _framing.decode(raw);
      if (payload == null) {
        if (_bootstrapCompleter?.isCompleted == false) {
          developer.log(
            'Discord Gateway bootstrap ignored a ${raw.runtimeType} frame.',
            name: 'flucord.discord.gateway',
            level: 900,
          );
        }
        return;
      }
      if (_bootstrapCompleter?.isCompleted == false) {
        developer.log(
          'Discord Gateway bootstrap frame: op=${payload['op']}, '
          'event=${payload['t'] ?? '-'}',
          name: 'flucord.discord.gateway',
        );
      }
      final actions = _protocol.accept(payload);
      for (final action in actions) {
        _apply(action);
      }
      if (payload['op'] == DiscordDesktopGatewayOpcode.hello) {
        _send(_protocol.canResume ? _protocol.resume() : _protocol.identify());
      }
    } on FormatException catch (error, stackTrace) {
      _lastBootstrapError = error;
      _logBootstrapFailure('frame-${_framing.encoding}', error, stackTrace);
      return;
    } on TypeError catch (error, stackTrace) {
      _lastBootstrapError = error;
      _logBootstrapFailure('frame-shape', error, stackTrace);
      return;
    }
  }

  void _apply(DiscordDesktopGatewayAction action) {
    switch (action) {
      case DiscordDesktopGatewaySend():
        _send(action.frame);
      case DiscordDesktopGatewayScheduleHeartbeat():
        _startHeartbeat(action.interval);
      case DiscordDesktopGatewayReconnect():
        _scheduleReconnect(immediate: action.immediate);
      case DiscordDesktopGatewayDispatch():
        _captureBootstrap(action);
        if (action.name == 'READY') {
          _emitStatus(DiscordGatewayStatus.connected);
          _subscribeReadyGuilds(action.data);
          _flushVoiceStates();
        }
        if (!_events.isClosed) {
          _events.add(
            DiscordGatewayDispatch(name: action.name, data: action.data),
          );
        }
    }
  }

  void _captureBootstrap(DiscordDesktopGatewayDispatch dispatch) {
    if (_bootstrapCompleter?.isCompleted != false) return;
    if (dispatch.name == 'READY') {
      final user = dispatch.data['user'];
      if (user is Map) _bootstrapUser = user.cast<String, Object?>();
      _bootstrapDirectChannels = _objects(dispatch.data['private_channels']);
      for (final guild in _objects(dispatch.data['guilds'])) {
        _captureGuild(guild);
      }
      _scheduleBootstrapCompletion(const Duration(seconds: 2));
    } else if (dispatch.name == 'GUILD_CREATE') {
      _captureGuild(dispatch.data);
      _scheduleBootstrapCompletion(const Duration(milliseconds: 350));
    } else if (dispatch.name == 'READY_SUPPLEMENTAL') {
      _scheduleBootstrapCompletion(const Duration(milliseconds: 350));
    }
  }

  void _captureGuild(Map<String, Object?> guild) {
    final id = guild['id'];
    if (id is! String) return;
    _bootstrapGuilds[id] = Map<String, Object?>.unmodifiable(guild);
    final channels = [
      ..._objects(guild['channels']),
      ..._objects(guild['threads']),
    ];
    if (channels.isNotEmpty) _bootstrapChannels[id] = channels;
  }

  void _scheduleBootstrapCompletion(Duration delay) {
    _bootstrapTimer?.cancel();
    _bootstrapTimer = Timer(delay, () {
      final snapshot = _snapshot();
      if (snapshot != null && _bootstrapCompleter?.isCompleted == false) {
        _bootstrapCompleter!.complete(snapshot);
      }
    });
  }

  DiscordDesktopWorkspaceSnapshot? _snapshot() {
    final user = _bootstrapUser;
    if (user == null) return null;
    return DiscordDesktopWorkspaceSnapshot(
      currentUser: user,
      guilds: _bootstrapGuilds.values,
      directChannels: _bootstrapDirectChannels,
      channelsByGuild: _bootstrapChannels,
    );
  }

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList(growable: false)
      : const [];

  void _subscribeReadyGuilds(Map<String, Object?> ready) {
    final guilds = ready['guilds'];
    if (guilds is! List) return;
    final subscriptions = <String, Map<String, Object?>>{};
    for (final guild in guilds.whereType<Map>()) {
      final id = guild['id'];
      if (id is! String) continue;
      subscriptions[id] = const {
        'typing': true,
        'threads': true,
        'activities': true,
        'member_updates': false,
        'members': <Object?>[],
        'channels': <String, Object?>{},
        'thread_member_lists': <Object?>[],
      };
    }
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
    final action = _protocol.heartbeatDue();
    _apply(action);
  }

  void _send(DiscordDesktopGatewayFrame frame) {
    final socket = _socket;
    if (socket == null || !socket.isOpen) return;
    final encoded = _framing.encode(frame.toJson());
    if (encoded is String) {
      socket.send(encoded);
    } else {
      socket.sendBinary(encoded as Uint8List);
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
    _scheduleReconnect();
  }

  void _onSocketError(Object error, StackTrace stackTrace) {
    _lastBootstrapError = error;
    _logBootstrapFailure('websocket-stream', error, stackTrace);
    _scheduleReconnect();
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

  void _scheduleReconnect({bool immediate = false}) {
    if (_closing || _reconnectTimer?.isActive == true) return;
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
  }) {
    final payload = <String, Object?>{
      'op': 4,
      'd': {
        'guild_id': guildId,
        'channel_id': channelId,
        'self_mute': selfMute,
        'self_deaf': selfDeaf,
      },
    };
    if (channelId == null) {
      _desiredVoiceStates.remove(guildId);
    } else {
      _desiredVoiceStates[guildId] = payload;
    }
    _send(DiscordDesktopGatewayFrame(4, payload['d']));
  }

  void _flushVoiceStates() {
    for (final payload in _desiredVoiceStates.values) {
      _send(DiscordDesktopGatewayFrame(4, payload['d']));
    }
  }

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
    _desiredVoiceStates.clear();
    _emitStatus(DiscordGatewayStatus.offline);
    await _events.close();
  }
}
