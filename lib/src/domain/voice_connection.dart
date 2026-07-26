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

final class VoiceParticipantStateEvent extends VoiceSignalingEvent {
  const VoiceParticipantStateEvent({
    required this.userId,
    required this.guildId,
    required this.channelId,
    required this.selfMuted,
    required this.selfDeafened,
    required this.serverMuted,
    required this.serverDeafened,
    required this.isStreaming,
    required this.isVideoEnabled,
  });

  final String userId;
  final String guildId;
  final String? channelId;
  final bool selfMuted;
  final bool selfDeafened;
  final bool serverMuted;
  final bool serverDeafened;
  final bool isStreaming;
  final bool isVideoEnabled;

  /// The same person, reported as having left.
  ///
  /// A departure is a voice state with no channel. Snapshot sources report who
  /// is present and never who left, so the absence has to be turned into an
  /// explicit event or the grid keeps showing them.
  VoiceParticipantStateEvent asDeparture() => VoiceParticipantStateEvent(
    userId: userId,
    guildId: guildId,
    channelId: null,
    selfMuted: selfMuted,
    selfDeafened: selfDeafened,
    serverMuted: serverMuted,
    serverDeafened: serverDeafened,
    isStreaming: false,
    isVideoEnabled: false,
  );
}

final class VoiceParticipant {
  const VoiceParticipant({
    required this.userId,
    this.ssrc,
    this.speakingFlags = 0,
    this.selfMuted = false,
    this.selfDeafened = false,
    this.serverMuted = false,
    this.serverDeafened = false,
    this.isStreaming = false,
    this.isVideoEnabled = false,
  });

  final String userId;
  final int? ssrc;
  final int speakingFlags;
  final bool selfMuted;
  final bool selfDeafened;
  final bool serverMuted;
  final bool serverDeafened;
  final bool isStreaming;
  final bool isVideoEnabled;

  bool get isSpeaking => speakingFlags != 0;
  bool get isMuted => selfMuted || serverMuted;
  bool get isDeafened => selfDeafened || serverDeafened;

  VoiceParticipant copyWith({
    int? ssrc,
    int? speakingFlags,
    bool? selfMuted,
    bool? selfDeafened,
    bool? serverMuted,
    bool? serverDeafened,
    bool? isStreaming,
    bool? isVideoEnabled,
  }) => VoiceParticipant(
    userId: userId,
    ssrc: ssrc ?? this.ssrc,
    speakingFlags: speakingFlags ?? this.speakingFlags,
    selfMuted: selfMuted ?? this.selfMuted,
    selfDeafened: selfDeafened ?? this.selfDeafened,
    serverMuted: serverMuted ?? this.serverMuted,
    serverDeafened: serverDeafened ?? this.serverDeafened,
    isStreaming: isStreaming ?? this.isStreaming,
    isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
  );
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
