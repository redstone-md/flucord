import '../../domain/voice_connection.dart';

import 'discord_voice_transport_cipher.dart';

final class DiscordVoiceReady {
  const DiscordVoiceReady({
    required this.ssrc,
    required this.ip,
    required this.port,
    required this.modes,
  });

  final int ssrc;
  final String ip;
  final int port;
  final List<String> modes;

  static DiscordVoiceReady? tryParse(Map<String, Object?> data) {
    final ssrc = data['ssrc'] as int?;
    final ip = data['ip'] as String?;
    final port = data['port'] as int?;
    final rawModes = data['modes'];
    if (ssrc == null ||
        ip == null ||
        ip.isEmpty ||
        port == null ||
        rawModes is! List) {
      return null;
    }
    return DiscordVoiceReady(
      ssrc: ssrc,
      ip: ip,
      port: port,
      modes: rawModes.whereType<String>().toList(growable: false),
    );
  }
}

final class DiscordVoiceSessionDescription {
  const DiscordVoiceSessionDescription({
    required this.mode,
    required this.secretKey,
    required this.daveProtocolVersion,
  });

  final String mode;
  final List<int> secretKey;
  final int daveProtocolVersion;

  static DiscordVoiceSessionDescription? tryParse(Map<String, Object?> data) {
    final mode = data['mode'] as String?;
    final rawKey = data['secret_key'];
    final daveVersion = data['dave_protocol_version'] as int? ?? 0;
    if (mode == null || mode.isEmpty || rawKey is! List) return null;
    final key = rawKey.whereType<int>().toList(growable: false);
    if (key.length != rawKey.length) return null;
    return DiscordVoiceSessionDescription(
      mode: mode,
      secretKey: key,
      daveProtocolVersion: daveVersion,
    );
  }
}

final class DiscordVoiceGatewayProtocol {
  DiscordVoiceGatewayProtocol({
    required this.credentials,
    required this.maxDaveProtocolVersion,
  });

  static const preferredModes = DiscordVoiceTransportMode.preferred;

  final VoiceServerCredentials credentials;
  final int maxDaveProtocolVersion;
  int sequenceAck = -1;

  /// `server_id` is the guild for guild voice and the channel for a DM or
  /// group-DM call (R08) — the credentials know which, so the identify body
  /// does not have to.
  Map<String, Object?> identify() => {
    'op': 0,
    'd': {
      'server_id': credentials.serverId,
      'user_id': credentials.userId,
      'session_id': credentials.sessionId,
      'token': credentials.token,
      'max_dave_protocol_version': maxDaveProtocolVersion,
    },
  };

  Map<String, Object?> resume() => {
    'op': 7,
    'd': {
      'server_id': credentials.serverId,
      'session_id': credentials.sessionId,
      'token': credentials.token,
      'seq_ack': sequenceAck,
    },
  };

  Map<String, Object?> heartbeat(int nonce) => {
    'op': 3,
    'd': {'t': nonce, 'seq_ack': sequenceAck},
  };

  Map<String, Object?> selectProtocol({
    required String address,
    required int port,
    required String mode,
  }) => {
    'op': 1,
    'd': {
      'protocol': 'udp',
      'data': {'address': address, 'port': port, 'mode': mode},
    },
  };

  Map<String, Object?> speaking({required int ssrc, required bool enabled}) => {
    'op': 5,
    'd': {'speaking': enabled ? 1 : 0, 'delay': 0, 'ssrc': ssrc},
  };

  void acceptSequence(Object? value) {
    if (value is int) sequenceAck = value;
  }

  String? selectMode(List<String> supported) {
    for (final mode in preferredModes) {
      if (supported.contains(mode)) return mode;
    }
    return null;
  }
}
