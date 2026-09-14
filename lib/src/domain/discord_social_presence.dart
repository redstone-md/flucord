import 'dart:async';

import 'discord_relationship.dart';

enum DiscordOnlineStatus { online, idle, doNotDisturb, invisible }

final class DiscordSocialRelationshipUpdate {
  factory DiscordSocialRelationshipUpdate({required String userId}) {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
    }
    return DiscordSocialRelationshipUpdate._(normalized);
  }

  const DiscordSocialRelationshipUpdate._(this.userId);

  final String userId;
}

abstract interface class DiscordSocialRelationshipEvents {
  Stream<DiscordSocialRelationshipUpdate> get relationshipUpdates;
}

abstract interface class DiscordSocialPresenceGateway {
  Future<void> setOnlineStatus(DiscordOnlineStatus status);
}

extension DiscordOnlineStatusPresence on DiscordOnlineStatus {
  DiscordPresenceStatus get presence => switch (this) {
    DiscordOnlineStatus.online => DiscordPresenceStatus.online,
    DiscordOnlineStatus.idle => DiscordPresenceStatus.idle,
    DiscordOnlineStatus.doNotDisturb => DiscordPresenceStatus.doNotDisturb,
    DiscordOnlineStatus.invisible => DiscordPresenceStatus.offline,
  };
}
