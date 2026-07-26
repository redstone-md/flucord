import 'discord_desktop_profile.dart';
import 'discord_gateway_framing.dart';

abstract final class DiscordDesktopGatewayOpcode {
  static const dispatch = 0;
  static const heartbeat = 1;
  static const identify = 2;
  static const voiceStateUpdate = 4;
  static const voiceServerPing = 5;
  static const resume = 6;
  static const reconnect = 7;
  static const invalidSession = 9;
  static const hello = 10;
  static const heartbeatAck = 11;
  static const callConnect = 13;
  static const guildSubscriptionsBulk = 37;
  static const qosHeartbeat = 40;
}

enum DiscordDesktopGatewayState {
  closed,
  identifying,
  resuming,
  established,
  reconnectPending,
}

final class DiscordDesktopGatewayFrame {
  const DiscordDesktopGatewayFrame(this.opcode, this.data);

  final int opcode;
  final Object? data;

  Map<String, Object?> toJson() => {'op': opcode, 'd': data};
}

sealed class DiscordDesktopGatewayAction {
  const DiscordDesktopGatewayAction();
}

final class DiscordDesktopGatewaySend extends DiscordDesktopGatewayAction {
  const DiscordDesktopGatewaySend(this.frame);

  final DiscordDesktopGatewayFrame frame;
}

final class DiscordDesktopGatewayScheduleHeartbeat
    extends DiscordDesktopGatewayAction {
  const DiscordDesktopGatewayScheduleHeartbeat(this.interval);

  final Duration interval;
}

final class DiscordDesktopGatewayReconnect extends DiscordDesktopGatewayAction {
  const DiscordDesktopGatewayReconnect({required this.immediate});

  final bool immediate;
}

final class DiscordDesktopGatewayDispatch extends DiscordDesktopGatewayAction {
  const DiscordDesktopGatewayDispatch({required this.name, required this.data});

  final String name;
  final Map<String, Object?> data;
}

final class DiscordDesktopGatewayProtocol {
  DiscordDesktopGatewayProtocol({
    required String token,
    required Map<String, Object?> properties,
    required this.profile,
    Map<String, Object?> presence = const {},
    Map<String, Object?> clientState = const {
      'guild_versions': <String, Object?>{},
    },
    this.usesLegacyCompression = false,
  }) : _token = _required(token, 'token'),
       properties = Map.unmodifiable({...properties}),
       presence = Map.unmodifiable({...presence}),
       clientState = Map.unmodifiable({...clientState}),
       _framing = DiscordGatewayFraming.forEncoding(profile.gatewayEncoding);

  final String _token;
  final DiscordGatewayFraming _framing;
  final Map<String, Object?> properties;
  final DiscordDesktopProtocolProfile profile;
  final Map<String, Object?> presence;
  final Map<String, Object?> clientState;
  final bool usesLegacyCompression;

  DiscordDesktopGatewayState _state = DiscordDesktopGatewayState.closed;
  int? _sequence;
  String? _sessionId;
  Uri? _resumeGatewayUri;
  bool _heartbeatAcknowledged = true;

  DiscordDesktopGatewayState get state => _state;
  int? get sequence => _sequence;
  Uri? get resumeGatewayUri => _resumeGatewayUri;
  bool get canResume => _sessionId != null && _sequence != null;

  DiscordDesktopGatewayFrame identify({bool fastConnect = false}) {
    _sequence = 0;
    _sessionId = null;
    _resumeGatewayUri = null;
    _state = DiscordDesktopGatewayState.identifying;
    return DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.identify, {
      'token': _token,
      'capabilities': profile.gatewayCapabilities,
      'properties': {...properties, 'is_fast_connect': fastConnect},
      if (!fastConnect) 'presence': presence,
      if (!fastConnect) 'compress': usesLegacyCompression,
      'client_state': fastConnect
          ? const {'guild_versions': <String, Object?>{}}
          : clientState,
    });
  }

  DiscordDesktopGatewayFrame resume() {
    if (!canResume) throw StateError('Gateway session cannot be resumed');
    _state = DiscordDesktopGatewayState.resuming;
    return DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.resume, {
      'token': _token,
      'session_id': _sessionId,
      'seq': _sequence,
    });
  }

  List<DiscordDesktopGatewayAction> accept(
    Map<String, Object?> payload, {
    Map<String, Object?> qos = const {},
  }) {
    final rawSequence = payload['s'];
    if (rawSequence is int) _sequence = rawSequence;
    final opcode = payload['op'];
    final data = payload['d'];
    switch (opcode) {
      case DiscordDesktopGatewayOpcode.dispatch:
        return _acceptDispatch(payload['t'], data);
      case DiscordDesktopGatewayOpcode.heartbeat:
        return [DiscordDesktopGatewaySend(_qosHeartbeat(qos))];
      case DiscordDesktopGatewayOpcode.reconnect:
        _state = DiscordDesktopGatewayState.reconnectPending;
        return const [DiscordDesktopGatewayReconnect(immediate: true)];
      case DiscordDesktopGatewayOpcode.invalidSession:
        if (data == true && canResume) {
          return [DiscordDesktopGatewaySend(resume())];
        }
        clearSession();
        return [DiscordDesktopGatewaySend(identify())];
      case DiscordDesktopGatewayOpcode.hello:
        if (data is! Map || data['heartbeat_interval'] is! num) return const [];
        _heartbeatAcknowledged = true;
        return [
          DiscordDesktopGatewayScheduleHeartbeat(
            Duration(
              milliseconds: (data['heartbeat_interval']! as num).round(),
            ),
          ),
        ];
      case DiscordDesktopGatewayOpcode.heartbeatAck:
        _heartbeatAcknowledged = true;
        return const [];
      default:
        return const [];
    }
  }

  DiscordDesktopGatewayAction heartbeatDue({
    Map<String, Object?> qos = const {},
  }) {
    if (!_heartbeatAcknowledged) {
      _state = DiscordDesktopGatewayState.reconnectPending;
      return const DiscordDesktopGatewayReconnect(immediate: true);
    }
    _heartbeatAcknowledged = false;
    return DiscordDesktopGatewaySend(_qosHeartbeat(qos));
  }

  List<DiscordDesktopGatewayFrame> guildSubscriptionFrames(
    Map<String, Map<String, Object?>> subscriptions,
  ) {
    final frames = <DiscordDesktopGatewayFrame>[];
    var batch = <String, Map<String, Object?>>{};
    var byteCount = 0;
    for (final entry in subscriptions.entries) {
      final entryBytes = _framing.measure([entry.key, entry.value]);
      if (batch.isNotEmpty &&
          byteCount + entryBytes > profile.maxGuildSubscriptionBytes) {
        frames.add(_subscriptionFrame(batch));
        batch = <String, Map<String, Object?>>{};
        byteCount = 0;
      }
      batch[entry.key] = Map.unmodifiable({...entry.value});
      byteCount += entryBytes;
    }
    if (batch.isNotEmpty) frames.add(_subscriptionFrame(batch));
    return frames;
  }

  void clearSession() {
    _sequence = null;
    _sessionId = null;
    _resumeGatewayUri = null;
    _state = DiscordDesktopGatewayState.closed;
  }

  List<DiscordDesktopGatewayAction> _acceptDispatch(
    Object? rawName,
    Object? rawData,
  ) {
    if (rawName is! String || rawData is! Map) return const [];
    final data = rawData.cast<String, Object?>();
    if (rawName == 'READY') {
      _sessionId = data['session_id'] as String?;
      final resumeUrl = data['resume_gateway_url'] as String?;
      _resumeGatewayUri = resumeUrl == null ? null : Uri.tryParse(resumeUrl);
      _state = DiscordDesktopGatewayState.established;
    } else if (rawName == 'READY_SUPPLEMENTAL' || rawName == 'RESUMED') {
      _state = DiscordDesktopGatewayState.established;
    }
    return [DiscordDesktopGatewayDispatch(name: rawName, data: data)];
  }

  DiscordDesktopGatewayFrame _qosHeartbeat(Map<String, Object?> qos) =>
      DiscordDesktopGatewayFrame(DiscordDesktopGatewayOpcode.qosHeartbeat, {
        'seq': _sequence,
        'qos': Map.unmodifiable({...qos}),
      });

  static DiscordDesktopGatewayFrame _subscriptionFrame(
    Map<String, Map<String, Object?>> subscriptions,
  ) => DiscordDesktopGatewayFrame(
    DiscordDesktopGatewayOpcode.guildSubscriptionsBulk,
    {'subscriptions': Map.unmodifiable(subscriptions)},
  );

  static String _required(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Value cannot be empty');
    }
    return normalized;
  }

  @override
  String toString() =>
      'DiscordDesktopGatewayProtocol(state: $_state, token: <redacted>)';
}
