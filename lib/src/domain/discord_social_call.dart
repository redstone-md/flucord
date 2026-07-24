enum DiscordSocialCallStatus {
  disconnected,
  joining,
  connecting,
  signalingConnected,
  connected,
  reconnecting,
  disconnecting,
  unknown,
}

final class DiscordSocialCallState {
  factory DiscordSocialCallState({
    required String lobbyId,
    required String currentUserId,
    required DiscordSocialCallStatus status,
    required Iterable<String> participantUserIds,
    required Iterable<String> speakingUserIds,
    required Iterable<String> locallyMutedUserIds,
    required bool selfMuted,
    required bool selfDeafened,
  }) {
    final normalizedLobbyId = _snowflake(lobbyId, 'lobbyId');
    final normalizedCurrentUserId = _snowflake(currentUserId, 'currentUserId');
    final participants = participantUserIds
        .map((id) => _snowflake(id, 'participantUserIds'))
        .toSet();
    final speaking = speakingUserIds
        .map((id) => _snowflake(id, 'speakingUserIds'))
        .toSet();
    final locallyMuted = locallyMutedUserIds
        .map((id) => _snowflake(id, 'locallyMutedUserIds'))
        .toSet();
    return DiscordSocialCallState._(
      lobbyId: normalizedLobbyId,
      currentUserId: normalizedCurrentUserId,
      status: status,
      participantUserIds: List.unmodifiable(participants),
      speakingUserIds: List.unmodifiable(speaking),
      locallyMutedUserIds: List.unmodifiable(locallyMuted),
      selfMuted: selfMuted,
      selfDeafened: selfDeafened,
    );
  }

  const DiscordSocialCallState._({
    required this.lobbyId,
    required this.currentUserId,
    required this.status,
    required this.participantUserIds,
    required this.speakingUserIds,
    required this.locallyMutedUserIds,
    required this.selfMuted,
    required this.selfDeafened,
  });

  final String lobbyId;
  final String currentUserId;
  final DiscordSocialCallStatus status;
  final List<String> participantUserIds;
  final List<String> speakingUserIds;
  final List<String> locallyMutedUserIds;
  final bool selfMuted;
  final bool selfDeafened;

  bool get isConnected => status == DiscordSocialCallStatus.connected;
  bool isSpeaking(String userId) => speakingUserIds.contains(userId);
  bool isLocallyMuted(String userId) => locallyMutedUserIds.contains(userId);
  bool get isActive => switch (status) {
    DiscordSocialCallStatus.disconnected => false,
    DiscordSocialCallStatus.unknown => false,
    _ => true,
  };

  static String _snowflake(String value, String name) {
    final normalized = value.trim();
    final parsed = BigInt.tryParse(normalized);
    if (parsed == null || parsed <= BigInt.zero || parsed.bitLength > 64) {
      throw ArgumentError.value(value, name, 'Must be a uint64 snowflake.');
    }
    return normalized;
  }
}

abstract interface class DiscordSocialCallGateway {
  Future<DiscordSocialCallState> startActivityCall(String lobbyId);

  Future<DiscordSocialCallState> setActivityCallMuted({
    required String lobbyId,
    required bool muted,
  });

  Future<DiscordSocialCallState> setActivityCallDeafened({
    required String lobbyId,
    required bool deafened,
  });

  Future<DiscordSocialCallState> setActivityParticipantMuted({
    required String lobbyId,
    required String userId,
    required bool muted,
  });

  Future<DiscordSocialCallState> leaveActivityCall(String lobbyId);
}

abstract interface class DiscordSocialCallEvents {
  Stream<DiscordSocialCallState> get activityCallEvents;
}
