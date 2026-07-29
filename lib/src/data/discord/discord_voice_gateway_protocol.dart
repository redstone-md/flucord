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
  /// `channel_id` and `video` are what the desktop client sends alongside the
  /// four identifying fields; `streams` is omitted because this session
  /// publishes no video, which is the same thing an empty list says.
  Map<String, Object?> identify() => {
    'op': 0,
    'd': {
      'server_id': credentials.serverId,
      'channel_id': credentials.channelId,
      'user_id': credentials.userId,
      'session_id': credentials.sessionId,
      'token': credentials.token,
      'max_dave_protocol_version': maxDaveProtocolVersion,
      'video': false,
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

  /// Opcode 12, which declares the SSRCs this session's camera will send on.
  ///
  /// The three are not negotiated: the desktop client derives them from the
  /// audio SSRC the voice `READY` handed out — video is one above it and the
  /// retransmission stream one above that — and announces the result. A client
  /// that picked its own numbers would send on SSRCs the server is not
  /// forwarding.
  ///
  /// Turning the camera off is the same frame with [enabled] false: the stream
  /// stays declared and inactive, which is what the renderer sends, rather than
  /// the SSRCs being withdrawn.
  Map<String, Object?> video({
    required int audioSsrc,
    required bool enabled,
    int width = 1280,
    int height = 720,
    int framesPerSecond = 30,
    int maxBitrate = 1200000,
  }) {
    final videoSsrc = audioSsrc + 1;
    return {
      'op': 12,
      'd': {
        'audio_ssrc': audioSsrc,
        'video_ssrc': videoSsrc,
        'rtx_ssrc': audioSsrc + 2,
        'streams': [
          {
            'type': 'video',
            // The single-stream rid the client falls back to when it has not
            // been told a simulcast layout; Flucord never sends more than one.
            'rid': '100',
            'ssrc': videoSsrc,
            'active': enabled,
            'quality': 100,
            'rtx_ssrc': audioSsrc + 2,
            'max_bitrate': maxBitrate,
            'max_framerate': framesPerSecond,
            'max_resolution': {
              'type': 'fixed',
              'width': width,
              'height': height,
            },
          },
        ],
      },
    };
  }

  /// The SSRC a camera's RTP goes out on, given the audio one.
  static int videoSsrcFor(int audioSsrc) => audioSsrc + 1;

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
