enum VoiceConnectionStatus {
  disconnected,
  joining,
  connecting,
  discovering,
  negotiating,
  ready,
  reconnecting,
  failure,
}

final class VoiceServerCredentials {
  const VoiceServerCredentials({
    required this.guildId,
    required this.channelId,
    required this.userId,
    required this.sessionId,
    required this.token,
    required this.endpoint,
  });

  final String guildId;
  final String channelId;
  final String userId;
  final String sessionId;
  final String token;
  final String endpoint;
}

final class VoiceTransportSession {
  const VoiceTransportSession({
    required this.guildId,
    required this.ssrc,
    required this.address,
    required this.port,
    required this.mode,
    required this.secretKey,
    required this.daveProtocolVersion,
  });

  final String guildId;
  final int ssrc;
  final String address;
  final int port;
  final String mode;
  final List<int> secretKey;
  final int daveProtocolVersion;
}

sealed class VoiceSignalingEvent {
  const VoiceSignalingEvent();
}

final class VoiceSignalingStatusEvent extends VoiceSignalingEvent {
  const VoiceSignalingStatusEvent(this.status, {this.error});

  final VoiceConnectionStatus status;
  final Object? error;
}

final class VoiceCredentialsReadyEvent extends VoiceSignalingEvent {
  const VoiceCredentialsReadyEvent(this.credentials);

  final VoiceServerCredentials credentials;
}

final class VoiceTransportReadyEvent extends VoiceSignalingEvent {
  const VoiceTransportReadyEvent(this.session);

  final VoiceTransportSession session;
}

final class VoiceDaveBinaryEvent extends VoiceSignalingEvent {
  const VoiceDaveBinaryEvent({
    required this.opcode,
    required this.payload,
    required this.sequence,
  });

  final int opcode;
  final List<int> payload;
  final int sequence;
}

final class VoiceSpeakingEvent extends VoiceSignalingEvent {
  const VoiceSpeakingEvent({
    required this.userId,
    required this.ssrc,
    required this.speakingFlags,
  });

  final String userId;
  final int ssrc;
  final int speakingFlags;

  bool get isSpeaking => speakingFlags != 0;
}

final class VoiceUserDisconnectedEvent extends VoiceSignalingEvent {
  const VoiceUserDisconnectedEvent(this.userId);

  final String userId;
}

abstract interface class VoiceSignalingService {
  Stream<VoiceSignalingEvent> get voiceEvents;

  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
  });

  Future<void> leaveVoiceChannel(String guildId);
}
