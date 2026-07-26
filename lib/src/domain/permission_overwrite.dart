import 'discord_permissions.dart';

/// What an overwrite's `id` points at.
enum PermissionOverwriteKind {
  role(0),
  member(1);

  const PermissionOverwriteKind(this.discordValue);

  final int discordValue;

  /// Anything that is not the member marker is a role overwrite: Discord's own
  /// reader treats the field as an enum with exactly two members and channels
  /// carry far more role overwrites than member ones, so an unknown value is
  /// safer read as a role than dropped.
  static PermissionOverwriteKind fromDiscordValue(Object? value) =>
      value == member.discordValue ? member : role;
}

/// One channel permission overwrite, as Discord serialises it.
///
/// `allow` and `deny` are independent masks, not a tri-state: a bit may appear
/// in neither (inherit), and the two are applied in a fixed order — deny first,
/// then allow — by whoever computes effective permissions.
final class DiscordPermissionOverwrite {
  const DiscordPermissionOverwrite({
    required this.id,
    required this.allow,
    required this.deny,
    this.kind = PermissionOverwriteKind.role,
  });

  /// The role id (when [kind] is a role) or user id (when it is a member). The
  /// guild's own id is the `@everyone` overwrite.
  final String id;
  final BigInt allow;
  final BigInt deny;
  final PermissionOverwriteKind kind;

  static DiscordPermissionOverwrite? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return DiscordPermissionOverwrite(
      id: id,
      allow: DiscordPermissions.parse(json['allow']),
      deny: DiscordPermissions.parse(json['deny']),
      kind: PermissionOverwriteKind.fromDiscordValue(json['type']),
    );
  }

  /// Reads a channel payload's `permission_overwrites` array into the map form
  /// every lookup wants, keyed by overwrite id. Malformed entries are skipped;
  /// a duplicate id keeps the last entry, as an object keyed assignment would.
  static Map<String, DiscordPermissionOverwrite> mapFromJson(Object? value) {
    if (value is! List) return const {};
    final overwrites = <String, DiscordPermissionOverwrite>{};
    for (final entry in value.whereType<Map>()) {
      final overwrite = fromJson(entry.cast<String, Object?>());
      if (overwrite != null) overwrites[overwrite.id] = overwrite;
    }
    return Map.unmodifiable(overwrites);
  }

  bool grants(BigInt mask) => DiscordPermissions.hasAll(allow, mask);

  bool denies(BigInt mask) => DiscordPermissions.hasAll(deny, mask);

  @override
  bool operator ==(Object other) =>
      other is DiscordPermissionOverwrite &&
      other.id == id &&
      other.allow == allow &&
      other.deny == deny &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, allow, deny, kind);

  @override
  String toString() =>
      'DiscordPermissionOverwrite($id, ${kind.name}, '
      'allow: $allow, deny: $deny)';
}
