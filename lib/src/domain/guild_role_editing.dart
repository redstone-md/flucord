part of 'guild_management.dart';

/// A guild role as the roles page needs it.
///
/// Wider than the sidebar's `CommunityRole`: hoisting, mentionability and the
/// `managed` flag have no bearing on what a member may read, so the workspace
/// projection never carried them, but every one of them is a control on this
/// surface.
final class GuildRole {
  const GuildRole({
    required this.id,
    required this.guildId,
    required this.name,
    required this.position,
    required this.permissions,
    this.colorValue = 0,
    this.hoist = false,
    this.mentionable = false,
    this.managed = false,
    this.iconHash,
    this.unicodeEmoji,
  });

  final String id;
  final String guildId;
  final String name;
  final int position;

  /// The role's permission bits. A [BigInt] because the field is 54 bits wide
  /// and arrives as a decimal string precisely because it outgrows a double.
  final BigInt permissions;

  final int colorValue;
  final bool hoist;
  final bool mentionable;

  /// Owned by an integration. Discord refuses every edit to one, so the roles
  /// page shows it and offers nothing.
  final bool managed;

  final String? iconHash;
  final String? unicodeEmoji;

  /// The `@everyone` role, which Discord keys by the guild's own id.
  bool get isEveryone => id == guildId;

  /// Top-to-bottom order, the way the settings page lists roles: the highest
  /// position first, ties broken by id so the list never reshuffles between
  /// frames over two roles Discord happens to have given the same position.
  static int compareForDisplay(GuildRole left, GuildRole right) {
    if (left.position != right.position) {
      return right.position.compareTo(left.position);
    }
    return left.id.compareTo(right.id);
  }
}

/// `POST /guilds/{id}/roles`.
final class GuildRoleDraft {
  const GuildRoleDraft({this.name, this.colorValue = 0, this.permissions});

  final String? name;
  final int colorValue;

  /// The bits the new role starts with. Null is Discord's own default of
  /// nothing at all, spelled as a nullable rather than `BigInt.zero` because a
  /// `BigInt` cannot be a `const` default.
  final BigInt? permissions;

  BigInt get grantedPermissions => permissions ?? BigInt.zero;

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    'color': colorValue,
    'colors': {
      'primary_color': colorValue,
      'secondary_color': null,
      'tertiary_color': null,
    },
    'permissions': grantedPermissions.toString(),
  };
}

/// A partial `PATCH /guilds/{id}/roles/{roleId}`.
///
/// Same tri-state discipline as [GuildOverviewPatch]: omitted means untouched,
/// and for `icon` and `unicode_emoji` an explicit null is what clears them.
final class GuildRoleEdit {
  GuildRoleEdit();

  final Map<String, Object?> _values = {};

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;
  Iterable<String> get keys => _values.keys;
  Object? operator [](String key) => _values[key];

  set name(String value) => _values['name'] = value;

  /// Permissions travel as a decimal string. Never as a number: the bitfield
  /// exceeds 2^53 and a JSON number would round the top bits away.
  set permissions(BigInt value) {
    if (value.isNegative) {
      throw ArgumentError.value(
        value,
        'permissions',
        'A permission bitfield is unsigned',
      );
    }
    _values['permissions'] = value.toString();
  }

  set colorValue(int value) {
    _values['color'] = value;
    _values['colors'] = {
      'primary_color': value,
      'secondary_color': null,
      'tertiary_color': null,
    };
  }

  set hoist(bool value) => _values['hoist'] = value;
  set mentionable(bool value) => _values['mentionable'] = value;

  /// A `data:` URI or `null`; a CDN hash is refused for the same reason the
  /// renderer drops it — the server has no use for the name it already gave us.
  set icon(String? value) {
    if (value != null && !value.startsWith('data:')) {
      throw ArgumentError.value(value, 'icon', 'Expected null or a data: URI');
    }
    _values['icon'] = value;
  }

  set unicodeEmoji(String? value) => _values['unicode_emoji'] = value;

  Map<String, Object?> toJson() => Map<String, Object?>.unmodifiable(_values);
}

/// One entry of the bare JSON array `PATCH /guilds/{id}/roles` takes.
final class RolePositionDelta {
  const RolePositionDelta({required this.id, required this.position});

  final String id;
  final int position;

  Map<String, Object?> toJson() => {'id': id, 'position': position};

  @override
  bool operator ==(Object other) =>
      other is RolePositionDelta &&
      other.id == id &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, position);

  @override
  String toString() => 'RolePositionDelta($id -> $position)';
}

/// Turns a reordered role list into the array Discord's roles page sends.
///
/// Both lists are held the way the settings page shows them — highest role
/// first — so the pass runs descending: index `i` of `L` roles is position
/// `L - 1 - i`.
///
/// `@everyone` is filtered out of the **result** but stays in the list while
/// the numbering is computed, which is the renderer's own arrangement and is
/// load-bearing. `@everyone` occupies position 0, so a ladder numbered without
/// it would put the lowest real role where `@everyone` sits and shift every
/// role in the guild down by one.
List<RolePositionDelta> roleReorderDeltas({
  required List<GuildRole> before,
  required List<GuildRole> after,
}) {
  final pinned = {
    for (final role in after)
      if (role.isEveryone) role.id,
  };
  return [
    for (final delta in calculatePositionDeltas<GuildRole>(
      oldOrdering: before,
      newOrdering: after,
      idOf: (role) => role.id,
      positionOf: (role) => role.position,
      ascending: false,
    ))
      if (!pinned.contains(delta.id))
        RolePositionDelta(id: delta.id, position: delta.position),
  ];
}
