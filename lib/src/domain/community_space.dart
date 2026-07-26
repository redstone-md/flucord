part of 'chat_models.dart';

enum SpaceKind { guild, directMessages }

final class CommunitySpace {
  static const directMessagesId = '@me';

  const CommunitySpace({
    required this.id,
    required this.name,
    required this.monogram,
    required this.colorValue,
    this.iconUrl,
    this.kind = SpaceKind.guild,
    this.ownerId,
    this.requiresMultiFactorAuth = false,
  });

  const CommunitySpace.directMessages()
    : id = directMessagesId,
      name = 'Direct Messages',
      monogram = 'DM',
      colorValue = 0xff456b5a,
      iconUrl = null,
      kind = SpaceKind.directMessages,
      ownerId = null,
      requiresMultiFactorAuth = false;

  final String id;
  final String name;
  final String monogram;
  final int colorValue;
  final String? iconUrl;
  final SpaceKind kind;

  /// The guild owner, who holds every permission regardless of roles.
  final String? ownerId;

  /// The guild's `mfa_level` is elevated, so moderation permissions are
  /// withheld from an account without two-factor auth.
  final bool requiresMultiFactorAuth;

  bool get isDirectMessages => kind == SpaceKind.directMessages;
}

final class CommunityRole {
  const CommunityRole({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.position,
    this.colorValue,
    this.permissions,
  });

  final String id;
  final String spaceId;
  final String name;
  final int position;
  final int? colorValue;

  /// The role's guild-wide permission bits, or null when this record came from
  /// a source that never carried them.
  ///
  /// Null is not zero. A role that genuinely grants nothing is a normal, common
  /// configuration, so a client that folded the two together would have to
  /// choose between hiding a whole guild it simply has no permission data for
  /// and trusting a lock-down as if it were an absence.
  final BigInt? permissions;

  /// True for the `@everyone` role, which Discord keys by the guild's own id.
  bool get isEveryone => id == spaceId;
}
