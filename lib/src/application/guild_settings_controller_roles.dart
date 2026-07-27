part of 'guild_settings_controller.dart';

extension GuildSettingsControllerRoles on GuildSettingsController {
  /// Whether [role] may be changed by this account.
  ///
  /// Two refusals beyond the permission bit: a role an integration owns, which
  /// Discord rejects every write to, and a role at or above the account's own
  /// highest, which is the hierarchy rule the bit alone does not express.
  bool canEditRole(GuildRole role) =>
      !role.managed && _capabilities.canEditRole(_asCommunityRole(role));

  /// Whether [role] may be deleted. `@everyone` never can be, by anybody.
  bool canDeleteRole(GuildRole role) =>
      !role.managed && _capabilities.canDeleteRole(_asCommunityRole(role));

  CommunityRole _asCommunityRole(GuildRole role) => CommunityRole(
    id: role.id,
    spaceId: role.guildId,
    name: role.name,
    position: role.position,
    permissions: role.permissions,
  );

  Future<bool> createRole(GuildRoleDraft draft) async {
    if (!_capabilities.canManageRoles) return false;
    return _run(() async {
      final role = await _repository.createRole(guildId: guildId, draft: draft);
      _roles = [..._roles, role]..sort(GuildRole.compareForDisplay);
    });
  }

  Future<bool> saveRole(GuildRole role, GuildRoleEdit edit) async {
    if (edit.isEmpty || !canEditRole(role)) return false;
    return _run(() async {
      final updated = await _repository.updateRole(
        guildId: guildId,
        roleId: role.id,
        edit: edit,
      );
      _roles = [
        for (final item in _roles)
          if (item.id == updated.id) updated else item,
      ]..sort(GuildRole.compareForDisplay);
    });
  }

  Future<bool> deleteRole(GuildRole role) async {
    if (!canDeleteRole(role)) return false;
    return _run(() async {
      await _repository.deleteRole(guildId: guildId, roleId: role.id);
      _roles = [
        for (final item in _roles)
          if (item.id != role.id) item,
      ];
    });
  }

  /// Moves [role] one place up (`-1`) or down (`1`) in the displayed list.
  ///
  /// The whole list is renumbered and the deltas are computed from the before
  /// and after orderings, because Discord's positions are not the list indices
  /// and a swap of two rows can move every role between them.
  ///
  /// The hierarchy check covers both ends: a moderator may not lift a role past
  /// their own highest, and may not reach one that already sits above it.
  Future<bool> moveRole(GuildRole role, {required int offset}) async {
    if (!canEditRole(role) || offset == 0) return false;
    final ordered = [..._roles]..sort(GuildRole.compareForDisplay);
    final index = ordered.indexWhere((item) => item.id == role.id);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= ordered.length) return false;
    final neighbour = ordered[target];
    if (neighbour.isEveryone || !canEditRole(neighbour)) return false;
    final reordered = [...ordered];
    reordered
      ..removeAt(index)
      ..insert(target, role);
    final deltas = roleReorderDeltas(before: ordered, after: reordered);
    if (deltas.isEmpty) return false;
    return _run(() async {
      await _repository.reorderRoles(guildId: guildId, deltas: deltas);
      final positions = {for (final delta in deltas) delta.id: delta.position};
      _roles = [
        for (final item in _roles)
          if (positions[item.id] case final int position)
            GuildRole(
              id: item.id,
              guildId: item.guildId,
              name: item.name,
              position: position,
              permissions: item.permissions,
              colorValue: item.colorValue,
              hoist: item.hoist,
              mentionable: item.mentionable,
              managed: item.managed,
              iconHash: item.iconHash,
              unicodeEmoji: item.unicodeEmoji,
            )
          else
            item,
      ]..sort(GuildRole.compareForDisplay);
    });
  }
}
