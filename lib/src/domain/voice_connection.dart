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

/// What one voice connection is filed under.
///
/// Discord allows a single voice connection per guild — walking from one voice
/// channel to another inside the same guild reuses it rather than opening a
/// second — so guild voice is keyed by the guild and the channel is merely
/// where the connection currently points. A call in a DM or group DM has no
/// guild at all: the channel *is* the connection's identity, which is why R08's
/// RTC store keys those by `guildId ?? channelId`.
///
/// Modelling that as a value instead of a bare string is what keeps a channel
/// id from silently standing in for a guild id. A DM call carries no guild, and
/// inventing one to satisfy a map key would have made every guild-shaped
/// lookup downstream — permissions, member lists, the roster — quietly wrong.
final class VoiceSessionKey {
  /// Guild voice, keyed by the guild that owns the channel.
  const VoiceSessionKey.guild(this.guildId) : callChannelId = null;

  /// A DM or group-DM call, keyed by the private channel it belongs to.
  const VoiceSessionKey.privateCall(this.callChannelId) : guildId = null;

  /// Null for a private call — those genuinely have no guild.
  final String? guildId;

  /// Null for guild voice, where the channel is not the connection's identity.
  final String? callChannelId;

  bool get isPrivateCall => guildId == null;

  @override
  bool operator ==(Object other) =>
      other is VoiceSessionKey &&
      other.guildId == guildId &&
      other.callChannelId == callChannelId;

  @override
  int get hashCode => Object.hash(guildId, callChannelId);

  @override
  String toString() => isPrivateCall
      ? 'VoiceSessionKey.privateCall($callChannelId)'
      : 'VoiceSessionKey.guild($guildId)';
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

  /// Absent for a DM or group-DM call.
  final String? guildId;
  final String channelId;
  final String userId;
  final String sessionId;
  final String token;
  final String endpoint;

  VoiceSessionKey get sessionKey => guildId == null
      ? VoiceSessionKey.privateCall(channelId)
      : VoiceSessionKey.guild(guildId!);

  /// The voice gateway identifies against `server_id`, which is the guild for
  /// guild voice and the channel for a private call (R08).
  String get serverId => guildId ?? channelId;
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

  /// Absent for a DM or group-DM call.
  final String? guildId;
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

  /// Absent for a DM or group-DM call participant.
  final String? guildId;
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

/// The media server relayed a viewer's picture-loss indication, which means a
/// viewer cannot decode what is arriving and only a fresh keyframe recovers
/// them.
final class VoiceKeyframeRequestedEvent extends VoiceSignalingEvent {
  const VoiceKeyframeRequestedEvent();
}

/// The media server did not get these packets of this client's pictures and
/// wants them again. Answered from the sender's history, or not at all: a
/// packet too old to be held is one the viewer has given up on already.
final class VoiceRetransmitRequestedEvent extends VoiceSignalingEvent {
  const VoiceRetransmitRequestedEvent({
    required this.ssrc,
    required this.sequences,
  });

  /// Whose packets: the video SSRC, or the camera's on a call.
  final int ssrc;
  final List<int> sequences;
}

/// What the far end reports receiving of this client's pictures, which is
/// the one number that separates "the network drops it" from "it never left".
final class VoiceReceiverReportEvent extends VoiceSignalingEvent {
  const VoiceReceiverReportEvent({
    required this.ssrc,
    required this.lossRatio,
    required this.cumulativeLost,
  });

  final int ssrc;

  /// Packets lost since the last report, 0 to 1.
  final double lossRatio;
  final int cumulativeLost;
}

abstract interface class VoiceSignalingService {
  Stream<VoiceSignalingEvent> get voiceEvents;

  /// Where the connection stands right now.
  ///
  /// Held as well as announced, because a status is a state rather than a
  /// notification: anything that subscribes after the connection came up —
  /// a controller rebinding to the same service, a surface opened later —
  /// would otherwise wait forever for an event that already happened, and
  /// show a working call as still joining.
  VoiceConnectionStatus get currentStatus;

  /// The transport in force, or null before one is negotiated. Held for the
  /// same reason.
  VoiceTransportSession? get currentSession;

  /// Who is currently seated in each voice channel, keyed by channel id.
  ///
  /// Discord shows a voice channel's occupants in the sidebar without anyone
  /// joining it, so this cannot be derived from the connection: the client is
  /// told about every voice state in a guild whether or not it is in the room.
  /// Exposing it separately is what lets the sidebar answer "who is in there"
  /// before the user decides to walk in.
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel;

  /// Fires whenever [seatedByChannel] changes.
  Stream<void> get seatedChanges;

  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    /// Whether the account's camera is on. Part of the same whole-state frame,
    /// so a join that forgot it would turn the camera off.
    bool selfVideo = false,
  });

  Future<void> leaveVoiceChannel(String guildId);
}
