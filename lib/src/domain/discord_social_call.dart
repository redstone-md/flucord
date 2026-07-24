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
    required DiscordSocialCallStatus status,
    required Iterable<String> participantUserIds,
    required bool selfMuted,
    required bool selfDeafened,
  }) {
    final normalizedLobbyId = _snowflake(lobbyId, 'lobbyId');
    final participants = participantUserIds
        .map((id) => _snowflake(id, 'participantUserIds'))
        .toSet();
    return DiscordSocialCallState._(
      lobbyId: normalizedLobbyId,
      status: status,
      participantUserIds: List.unmodifiable(participants),
      selfMuted: selfMuted,
      selfDeafened: selfDeafened,
    );
  }

  const DiscordSocialCallState._({
    required this.lobbyId,
    required this.status,
    required this.participantUserIds,
    required this.selfMuted,
    required this.selfDeafened,
  });

  final String lobbyId;
  final DiscordSocialCallStatus status;
  final List<String> participantUserIds;
  final bool selfMuted;
  final bool selfDeafened;

  bool get isConnected => status == DiscordSocialCallStatus.connected;
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

  Future<DiscordSocialCallState> leaveActivityCall(String lobbyId);
}

abstract interface class DiscordSocialCallEvents {
  Stream<DiscordSocialCallState> get activityCallEvents;
}
