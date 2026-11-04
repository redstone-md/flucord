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
    this.premiumTier = 0,
    this.memberCount,
    this.joinedAt,
  });

  const CommunitySpace.directMessages()
    : id = directMessagesId,
      name = 'Direct Messages',
      monogram = 'DM',
      colorValue = 0xff456b5a,
      iconUrl = null,
      kind = SpaceKind.directMessages,
      ownerId = null,
      requiresMultiFactorAuth = false,
      premiumTier = 0,
      memberCount = null,
      joinedAt = null;

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

  /// The guild's boost level, Discord's `premium_tier`: 0 none, 1 to 3 the
  /// boost levels. Levels 2 and 3 raise the upload limit for every member of
  /// the server, which is the one thing this client reads it for.
  final int premiumTier;

  /// How many members the guild had when the gateway last sent it in full.
  /// Null when unknown, such as for a server read back from the cache.
  final int? memberCount;

  /// When the account joined the guild. Null when unknown.
  final DateTime? joinedAt;

  bool get isDirectMessages => kind == SpaceKind.directMessages;

  /// This record, with the member count and join date of [earlier] where
  /// this one has none. A guild update carries neither.
  CommunitySpace keepingSummaryOf(CommunitySpace earlier) => CommunitySpace(
    id: id,
    name: name,
    monogram: monogram,
    colorValue: colorValue,
    iconUrl: iconUrl,
    kind: kind,
    ownerId: ownerId,
    requiresMultiFactorAuth: requiresMultiFactorAuth,
    premiumTier: premiumTier,
    memberCount: memberCount ?? earlier.memberCount,
    joinedAt: joinedAt ?? earlier.joinedAt,
  );
}

final class CommunityRole {
  const CommunityRole({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.position,
    this.colorValue,
    this.permissions,
    this.hoist = false,
  });

  final String id;
  final String spaceId;
  final String name;
  final int position;
  final int? colorValue;

  /// Whether the member list shows the role's members in a group of its own.
  final bool hoist;

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

  /// Equal when every field matches, so a gateway diff can skip a role that
  /// did not change.
  @override
  bool operator ==(Object other) =>
      other is CommunityRole &&
      other.id == id &&
      other.spaceId == spaceId &&
      other.name == name &&
      other.position == position &&
      other.colorValue == colorValue &&
      other.hoist == hoist &&
      other.permissions == permissions;

  @override
  int get hashCode =>
      Object.hash(id, spaceId, name, position, colorValue, hoist, permissions);
}

/// The roles a member holds in one server, highest first.
///
/// Built from the workspace's roles by id, so a role's name, place, colour and
/// grouping are read from one record and follow it when it changes.
final class HeldRoles {
  const HeldRoles(this.highestFirst);

  /// The roles [member] holds in [spaceId] that [roleOf] knows. Two roles at
  /// the same position are ordered as Discord orders them: by id.
  factory HeldRoles.of(
    Member member,
    String spaceId,
    CommunityRole? Function(String roleId) roleOf,
  ) => HeldRoles.ofIds(
    member.membershipIn(spaceId)?.roleIds ?? const [],
    roleOf,
  );

  /// The roles named by [roleIds] that [roleOf] knows, highest first.
  factory HeldRoles.ofIds(
    Iterable<String> roleIds,
    CommunityRole? Function(String roleId) roleOf,
  ) {
    if (roleIds.isEmpty) return none;
    return HeldRoles(
      [for (final roleId in roleIds) ?roleOf(roleId)]..sort(
        (left, right) => left.position != right.position
            ? right.position.compareTo(left.position)
            : DiscordSnowflake.compare(left.id, right.id),
      ),
    );
  }

  static const none = HeldRoles([]);

  final List<CommunityRole> highestFirst;

  CommunityRole? get top => highestFirst.isEmpty ? null : highestFirst.first;

  /// The role whose group the member list shows the member in.
  CommunityRole? get hoisted {
    for (final role in highestFirst) {
      if (role.hoist) return role;
    }
    return null;
  }

  /// The colour of the member's name: that of the highest role with one.
  int? get nameColor {
    for (final role in highestFirst) {
      if (role.colorValue case final color?) return color;
    }
    return null;
  }

  /// The name of the highest role, or [member]'s own label when they hold
  /// none here.
  String nameFor(Member member) => top?.name ?? member.role;
}
