import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'discord_desktop_gateway_protocol.dart';
import 'discord_desktop_profile.dart';
import 'discord_desktop_websocket.dart';
import 'discord_gateway_client.dart';
import 'discord_rest_client.dart';

final class DiscordDesktopWorkspaceSnapshot {
  DiscordDesktopWorkspaceSnapshot({
    required Map<String, Object?> currentUser,
    required Iterable<Map<String, Object?>> guilds,
    required Iterable<Map<String, Object?>> directChannels,
    required Map<String, List<Map<String, Object?>>> channelsByGuild,
  }) : currentUser = Map.unmodifiable({...currentUser}),
       guilds = List.unmodifiable(
         guilds.map((guild) => Map.unmodifiable({...guild})),
       ),
       directChannels = List.unmodifiable(
         directChannels.map((channel) => Map.unmodifiable({...channel})),
       ),
       channelsByGuild = Map.unmodifiable({
         for (final entry in channelsByGuild.entries)
           entry.key: List.unmodifiable(
             entry.value.map((channel) => Map.unmodifiable({...channel})),
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
       );

  final DiscordDesktopProtocolProfile profile;
  final DiscordDesktopGatewayProtocol _protocol;
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
    await connect(gatewayUrl);
    return _bootstrapCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        final snapshot = _snapshot();
        if (snapshot == null) {
          throw const DiscordApiException(
            statusCode: 504,
            message: 'Discord Gateway bootstrap timed out',
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
    final uri = base.replace(
      queryParameters: {'encoding': 'json', 'v': '${profile.gatewayVersion}'},
    );
    try {
      _socket = await _socketConnector.connect(uri);
      _socket!.messages.listen(
        _accept,
        onDone: _onDone,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } on Object {
      _scheduleReconnect();
    }
  }

  void _accept(Object? raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final payload = decoded.cast<String, Object?>();
      final actions = _protocol.accept(payload);
      for (final action in actions) {
        _apply(action);
      }
      if (payload['op'] == DiscordDesktopGatewayOpcode.hello) {
        _send(_protocol.canResume ? _protocol.resume() : _protocol.identify());
      }
    } on FormatException {
      return;
    } on TypeError {
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
    _bootstrapGuilds[id] = Map.unmodifiable({...guild});
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
    if (_socket?.isOpen ?? false) {
      _socket!.send(jsonEncode(frame.toJson()));
    }
  }

  void _onDone() {
    final code = _socket?.closeCode;
    if (code == 4004) {
      _emitStatus(DiscordGatewayStatus.offline);
      return;
    }
    _scheduleReconnect();
  }

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
