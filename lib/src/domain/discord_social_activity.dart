enum DiscordSocialActivityInviteType { join, joinRequest, unknown }

typedef DiscordSocialActivitySecretFactory = String Function();

final class DiscordSocialActivityInvite {
  factory DiscordSocialActivityInvite({
    required String applicationId,
    required String parentApplicationId,
    required String channelId,
    required String messageId,
    required String senderId,
    required String partyId,
    required String sessionId,
    required DiscordSocialActivityInviteType type,
    required bool isValid,
  }) {
    return DiscordSocialActivityInvite._(
      applicationId: _snowflake(applicationId, 'applicationId'),
      parentApplicationId: _uint64(
        parentApplicationId,
        'parentApplicationId',
        allowZero: true,
      ),
      channelId: _snowflake(channelId, 'channelId'),
      messageId: _snowflake(messageId, 'messageId'),
      senderId: _snowflake(senderId, 'senderId'),
      partyId: partyId.trim(),
      sessionId: sessionId.trim(),
      type: type,
      isValid: isValid,
    );
  }

  const DiscordSocialActivityInvite._({
    required this.applicationId,
    required this.parentApplicationId,
    required this.channelId,
    required this.messageId,
    required this.senderId,
    required this.partyId,
    required this.sessionId,
    required this.type,
    required this.isValid,
  });

  final String applicationId;
  final String parentApplicationId;
  final String channelId;
  final String messageId;
  final String senderId;
  final String partyId;
  final String sessionId;
  final DiscordSocialActivityInviteType type;
  final bool isValid;

  String get key => messageId;

  static String _snowflake(String value, String name) {
    return _uint64(value, name, allowZero: false);
  }

  static String _uint64(String value, String name, {required bool allowZero}) {
    final normalized = value.trim();
    final parsed = BigInt.tryParse(normalized);
    if (parsed == null ||
        (allowZero ? parsed < BigInt.zero : parsed <= BigInt.zero) ||
        parsed.bitLength > 64) {
      throw ArgumentError.value(value, name, 'Must be a uint64 snowflake.');
    }
    return normalized;
  }
}

final class DiscordSocialActivitySession {
  factory DiscordSocialActivitySession({required String lobbyId}) {
    final normalized = lobbyId.trim();
    final parsed = BigInt.tryParse(normalized);
    if (parsed == null || parsed <= BigInt.zero || parsed.bitLength > 64) {
      throw ArgumentError.value(lobbyId, 'lobbyId', 'Must be a uint64.');
    }
    return DiscordSocialActivitySession._(normalized);
  }

  const DiscordSocialActivitySession._(this.lobbyId);

  final String lobbyId;
}

final class DiscordSocialActivityInviteEvent {
  const DiscordSocialActivityInviteEvent({
    required this.invite,
    required this.updated,
  });

  final DiscordSocialActivityInvite invite;
  final bool updated;
}

abstract interface class DiscordSocialActivityGateway {
  Future<DiscordSocialActivitySession> sendActivityInvite(String userId);

  Future<DiscordSocialActivitySession> acceptActivityInvite(
    DiscordSocialActivityInvite invite,
  );
}

abstract interface class DiscordSocialActivityEvents {
  Stream<DiscordSocialActivityInviteEvent> get activityInviteEvents;
}
