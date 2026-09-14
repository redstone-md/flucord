import '../domain/discord_relationship.dart';

abstract final class DiscordSocialRelationshipMapper {
  static List<DiscordRelationship> decode(Object? payload) {
    if (payload is! List<Object?>) {
      throw const FormatException('Relationships payload must be a list.');
    }
    return List.unmodifiable(payload.map(_decodeRelationship));
  }

  static DiscordRelationship _decodeRelationship(Object? payload) {
    if (payload is! Map<Object?, Object?>) {
      throw const FormatException('Relationship entry must be a map.');
    }
    final id = switch (payload['id']) {
      final String value => value,
      final int value => value.toString(),
      _ => '',
    };
    if (id.trim().isEmpty) {
      throw const FormatException('Relationship user id is missing.');
    }
    return DiscordRelationship(
      user: DiscordRelationshipUser(
        id: id,
        displayName: _text(payload['display_name']) ?? '',
        username: _text(payload['username']),
        avatarUrl: _text(payload['avatar_url']),
        status: _presence(payload['status']),
        isProvisional: payload['is_provisional'] == true,
        activity: _activity(payload['activity']),
      ),
      kind: _relationshipKind(payload['relationship_type']),
      isSpamRequest: payload['is_spam_request'] == true,
    );
  }

  static DiscordRelationshipKind _relationshipKind(Object? value) {
    return switch (_enumKey(value)) {
      'friend' => DiscordRelationshipKind.friend,
      'incomingrequest' ||
      'pendingincoming' => DiscordRelationshipKind.incomingRequest,
      'outgoingrequest' ||
      'pendingoutgoing' => DiscordRelationshipKind.outgoingRequest,
      'blocked' => DiscordRelationshipKind.blocked,
      'implicit' => DiscordRelationshipKind.implicit,
      _ => DiscordRelationshipKind.unknown,
    };
  }

  static DiscordPresenceStatus _presence(Object? value) {
    return switch (_enumKey(value)) {
      'online' => DiscordPresenceStatus.online,
      'idle' => DiscordPresenceStatus.idle,
      'donotdisturb' || 'dnd' => DiscordPresenceStatus.doNotDisturb,
      'offline' => DiscordPresenceStatus.offline,
      _ => DiscordPresenceStatus.unknown,
    };
  }

  static DiscordRelationshipActivity? _activity(Object? value) {
    if (value == null) return null;
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Relationship activity must be a map.');
    }
    final name = _text(value['name']);
    if (name == null) {
      throw const FormatException('Relationship activity name is missing.');
    }
    return DiscordRelationshipActivity(
      name: name,
      details: _text(value['details']),
      state: _text(value['state']),
    );
  }

  static String _enumKey(Object? value) => (value is String ? value : '')
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '');

  static String? _text(Object? value) {
    final normalized = value is String ? value.trim() : '';
    return normalized.isEmpty ? null : normalized;
  }
}
