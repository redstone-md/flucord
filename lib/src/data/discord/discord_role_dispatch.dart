/// One `GUILD_ROLE_CREATE`, `GUILD_ROLE_UPDATE` or `GUILD_ROLE_DELETE`.
///
/// Several places keep a guild's raw role payloads: the member-list directory,
/// the bootstrap, and the bot transport. Each folds the same dispatch through
/// [applyTo], so they cannot disagree about what a role change means.
final class DiscordRoleDispatch {
  const DiscordRoleDispatch._({
    required this.guildId,
    required this.roleId,
    this.role,
  });

  /// The dispatch [name] carries, or null when it is not a role dispatch or
  /// names no guild or role.
  static DiscordRoleDispatch? read(String name, Map<String, Object?> data) {
    final guildId = data['guild_id'];
    if (guildId is! String) return null;
    switch (name) {
      case 'GUILD_ROLE_CREATE' || 'GUILD_ROLE_UPDATE':
        final role = data['role'];
        if (role is! Map || role['id'] is! String) return null;
        return DiscordRoleDispatch._(
          guildId: guildId,
          roleId: role['id']! as String,
          role: role.cast<String, Object?>(),
        );
      case 'GUILD_ROLE_DELETE':
        final roleId = data['role_id'];
        if (roleId is! String) return null;
        return DiscordRoleDispatch._(guildId: guildId, roleId: roleId);
    }
    return null;
  }

  final String guildId;
  final String roleId;

  /// The role as it is now. Null when it was deleted.
  final Map<String, Object?>? role;

  /// [roles] after this change. A changed role keeps its place; a new one goes
  /// last.
  List<Map<String, Object?>> applyTo(List<Map<String, Object?>> roles) {
    final next = role;
    if (next == null) {
      return [
        for (final held in roles)
          if (held['id'] != roleId) held,
      ];
    }
    final known = roles.any((held) => held['id'] == roleId);
    return [
      for (final held in roles) held['id'] == roleId ? next : held,
      if (!known) next,
    ];
  }
}
