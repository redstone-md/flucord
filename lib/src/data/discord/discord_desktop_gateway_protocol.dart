import 'discord_desktop_profile.dart';
import 'discord_gateway_framing.dart';

abstract final class DiscordDesktopGatewayOpcode {
  static const dispatch = 0;
  static const heartbeat = 1;
  static const identify = 2;
  static const presenceUpdate = 3;
  static const voiceStateUpdate = 4;
  static const voiceServerPing = 5;
  static const resume = 6;
  static const reconnect = 7;
  static const invalidSession = 9;
  static const hello = 10;
  static const heartbeatAck = 11;
  static const callConnect = 13;
  static const streamCreate = 18;
  static const streamDelete = 19;
  static const streamWatch = 20;
  static const streamPing = 21;
  static const streamSetPaused = 22;
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

  /// Where a dispatch whose `d` is a bare JSON array is delivered.
  ///
  /// `PRESENCES_REPLACE` and `SESSIONS_REPLACE` are the two events whose whole
  /// payload is an array rather than an object — R07 confirms both mappers are
  /// handed the dispatch directly and start with `e.map(...)`. Every other
  /// dispatch is an object, so the array is wrapped under this key instead of
  /// widening the payload type of every consumer in the client; a dispatch
  /// that simply refused to carry an array dropped both events silently.
  static const arrayPayloadKey = 'items';

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
  final Map<String, Object?> clientState;
  final bool usesLegacyCompression;

  /// The presence IDENTIFY carries.
  ///
  /// R07 proves IDENTIFY embeds the very object opcode 3 sends, so a reconnect
  /// re-asserts the presence this client last committed rather than reverting
  /// the account to its default while the settings blob reloads. It starts
  /// empty because nothing is known about the account before the first READY.
  Map<String, Object?> presence;

  /// Supplies the `client_state` block at the moment IDENTIFY is built.
  ///
  /// R03 computes several of those fields from caches that only exist once a
  /// session has run, so the block cannot be fixed at construction: a socket
  /// built before the first `READY` would echo versions of zero forever, and a
  /// reconnect would ask for a full payload it already holds.
  Map<String, Object?> Function()? clientStateProvider;

  DiscordDesktopGatewayState _state = DiscordDesktopGatewayState.closed;
  int? _sequence;
  String? _sessionId;
  Uri? _resumeGatewayUri;
  bool _heartbeatAcknowledged = true;

  DiscordDesktopGatewayState get state => _state;
  int? get sequence => _sequence;
  Uri? get resumeGatewayUri => _resumeGatewayUri;
  bool get canResume => _sessionId != null && _sequence != null;

  /// The session READY named, or `null` before one exists.
  ///
  /// An interaction has to carry it: the session is how Discord routes the
  /// application's response back to this client rather than another one signed
  /// into the same account.
  String? get sessionId => _sessionId;

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
          : clientStateProvider?.call() ?? clientState,
    });
  }

  /// Opcode 3. R07: exactly four keys, and no `guild_id` or `broadcast`.
  DiscordDesktopGatewayFrame presenceUpdate(Map<String, Object?> payload) {
    presence = Map.unmodifiable({...payload});
    return DiscordDesktopGatewayFrame(
      DiscordDesktopGatewayOpcode.presenceUpdate,
      presence,
    );
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
    if (rawName is! String) return const [];
    if (rawData is List) {
      return [
        DiscordDesktopGatewayDispatch(
          name: rawName,
          data: {DiscordDesktopGatewayDispatch.arrayPayloadKey: rawData},
        ),
      ];
    }
    if (rawData is! Map) return const [];
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
