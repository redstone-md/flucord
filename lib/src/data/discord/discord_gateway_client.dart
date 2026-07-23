import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum DiscordGatewayStatus { offline, connecting, connected, reconnecting }

sealed class DiscordGatewayEvent {
  const DiscordGatewayEvent();
}

final class DiscordGatewayStatusEvent extends DiscordGatewayEvent {
  const DiscordGatewayStatusEvent(this.status);

  final DiscordGatewayStatus status;
}

final class DiscordGatewayDispatch extends DiscordGatewayEvent {
  const DiscordGatewayDispatch({required this.name, required this.data});

  final String name;
  final Map<String, Object?> data;
}

final class DiscordGatewayProtocol {
  DiscordGatewayProtocol({required this.token, required this.intents});

  final String token;
  final int intents;
  int? sequence;
  String? sessionId;
  String? resumeGatewayUrl;

  Map<String, Object?> identify() => {
    'op': 2,
    'd': {
      'token': token,
      'intents': intents,
      'properties': {
        'os': Platform.operatingSystem,
        'browser': 'flucord',
        'device': 'flucord',
      },
    },
  };

  Map<String, Object?> heartbeat() => {'op': 1, 'd': sequence};

  Map<String, Object?> resume() => {
    'op': 6,
    'd': {'token': token, 'session_id': sessionId, 'seq': sequence},
  };

  void accept(Map<String, Object?> payload) {
    if (payload['s'] is int) sequence = payload['s']! as int;
    if (payload['op'] == 0 && payload['t'] == 'READY') {
      final data = (payload['d']! as Map).cast<String, Object?>();
      sessionId = data['session_id'] as String?;
      resumeGatewayUrl = data['resume_gateway_url'] as String?;
    }
  }

  bool get canResume => sessionId != null && sequence != null;

  void clearSession() {
    sequence = null;
    sessionId = null;
    resumeGatewayUrl = null;
  }
}

final class DiscordGatewayClient {
  DiscordGatewayClient({required String botToken})
    : _protocol = DiscordGatewayProtocol(
        token: botToken.trim(),
        intents: guildsIntent | guildMessagesIntent | messageContentIntent,
      );

  static const guildsIntent = 1 << 0;
  static const guildMessagesIntent = 1 << 9;
  static const messageContentIntent = 1 << 15;

  final DiscordGatewayProtocol _protocol;
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();
  final Random _random = Random();

  WebSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _initialHeartbeatTimer;
  Timer? _reconnectTimer;
  String? _gatewayUrl;
  bool _heartbeatAcknowledged = true;
  bool _closing = false;

  Stream<DiscordGatewayEvent> get events => _events.stream;

  Future<void> connect(String gatewayUrl) async {
    _gatewayUrl = gatewayUrl;
    _closing = false;
    await _open();
  }

  Future<void> _open() async {
    if (_closing) return;
    _emitStatus(
      _protocol.canResume
          ? DiscordGatewayStatus.reconnecting
          : DiscordGatewayStatus.connecting,
    );
    final baseUrl = _protocol.resumeGatewayUrl ?? _gatewayUrl;
    if (baseUrl == null) return;
    final uri = Uri.parse(
      baseUrl,
    ).replace(queryParameters: {'v': '10', 'encoding': 'json'});
    try {
      _socket = await WebSocket.connect(uri.toString());
      _socket!.listen(
        _onData,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(Object? raw) {
    if (raw is! String) return;
    final payload = (jsonDecode(raw) as Map).cast<String, Object?>();
    _protocol.accept(payload);
    switch (payload['op']) {
      case 0:
        final name = payload['t'] as String?;
        final data = payload['d'];
        if (name == 'READY') {
          _emitStatus(DiscordGatewayStatus.connected);
        }
        if (name != null && data is Map) {
          _events.add(
            DiscordGatewayDispatch(
              name: name,
              data: data.cast<String, Object?>(),
            ),
          );
        }
      case 1:
        _send(_protocol.heartbeat());
      case 7:
        _scheduleReconnect(immediate: true);
      case 9:
        if (payload['d'] != true) _protocol.clearSession();
        _scheduleReconnect();
      case 10:
        final data = (payload['d']! as Map).cast<String, Object?>();
        final interval = Duration(
          milliseconds: (data['heartbeat_interval']! as num).round(),
        );
        _startHeartbeat(interval);
        _send(_protocol.canResume ? _protocol.resume() : _protocol.identify());
      case 11:
        _heartbeatAcknowledged = true;
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
    if (!_heartbeatAcknowledged) {
      _scheduleReconnect(immediate: true);
      return;
    }
    _heartbeatAcknowledged = false;
    _send(_protocol.heartbeat());
  }

  void _send(Map<String, Object?> payload) {
    if (_socket?.readyState == WebSocket.open) {
      _socket!.add(jsonEncode(payload));
    }
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

  void _emitStatus(DiscordGatewayStatus status) {
    if (!_events.isClosed) _events.add(DiscordGatewayStatusEvent(status));
  }

  Future<void> close() async {
    _closing = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _initialHeartbeatTimer?.cancel();
    await _socket?.close();
    _emitStatus(DiscordGatewayStatus.offline);
    await _events.close();
  }
}
