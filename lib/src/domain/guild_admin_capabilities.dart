part of 'workspace_permissions.dart';

/// What the signed-in account may administer in one guild.
///
/// One object rather than seven scattered permission tests so the settings
/// window asks the question once and every section agrees. It also keeps the
/// hierarchy rule in a single place: role position is not a permission bit, so
/// a surface that only checked `MANAGE_ROLES` would happily offer an edit
/// Discord refuses — and refuse it *after* the moderator typed the change.
final class GuildAdminCapabilities {
  GuildAdminCapabilities._(this._permissions, this.spaceId)
    : _bits = _permissions.inSpace(spaceId);

  final WorkspacePermissions _permissions;
  final String spaceId;

  /// Guild-wide permissions, or `null` when this client was never told them.
  final BigInt? _bits;

  /// Whether the account owns the guild. The owner sits above every role and
  /// is the only member the hierarchy rule does not bind.
  bool get isOwner {
    final space = _permissions._workspace.spaces
        .where((item) => item.id == spaceId)
        .firstOrNull;
    return space?.ownerId != null && space!.ownerId == _permissions._memberId;
  }

  bool get canManageGuild => _has(DiscordPermissions.manageGuild);
  bool get canManageRoles => _has(DiscordPermissions.manageRoles);
  bool get canManageChannels => _has(DiscordPermissions.manageChannels);
  bool get canBanMembers => _has(DiscordPermissions.banMembers);
  bool get canKickMembers => _has(DiscordPermissions.kickMembers);
  bool get canCreateInvite => _has(DiscordPermissions.createInstantInvite);
  bool get canViewAuditLog => _has(DiscordPermissions.viewAuditLog);

  /// Creating, editing and deleting the server's scheduled events.
  bool get canManageEvents => _has(DiscordPermissions.manageEvents);

  /// Whether the account may grant [permission] to a role.
  ///
  /// Discord refuses to let a member hand out a permission they do not hold
  /// themselves — otherwise anyone with MANAGE_ROLES could grant themselves
  /// ADMINISTRATOR through a role they control. Offering the switch anyway
  /// would only earn a rejection, and would read as a privilege the account
  /// does not have.
  /// Whether the account may create an invite for one specific channel.
  ///
  /// CREATE_INSTANT_INVITE is routinely granted guild-wide and then taken back
  /// on individual channels, so the guild-wide answer alone offers the action
  /// exactly where the server will refuse it.
  bool canInviteToChannel(ConversationChannel channel) =>
      _permissions.can(DiscordPermissions.createInstantInvite, channel);

  bool canGrant(BigInt permission) =>
      isOwner || _has(DiscordPermissions.administrator) || _has(permission);

  /// Whether any section of the settings window has something to show. A
  /// member who may do none of it is not shown a door into an empty room.
  bool get hasAnySurface =>
      canManageGuild ||
      canManageRoles ||
      canManageChannels ||
      canBanMembers ||
      canKickMembers ||
      canViewAuditLog;

  /// The position of the account's highest role, or `null` when unknown.
  ///
  /// `@everyone` counts as position 0, which is why a member holding nothing
  /// else answers 0 rather than null: that is a real answer, and it correctly
  /// bars them from editing every role including `@everyone` itself.
  int? get highestRolePosition {
    if (_bits == null) return null;
    final membership = _permissions._membershipIn(spaceId);
    if (membership == null) return null;
    final held = membership.roleIds.toSet();
    var highest = 0;
    for (final role in _permissions._workspace.roles) {
      if (role.spaceId != spaceId) continue;
      if (!held.contains(role.id)) continue;
      if (role.position > highest) highest = role.position;
    }
    return highest;
  }

  /// Whether the account may change [role].
  ///
  /// Three separate refusals, and each one is a request Discord would reject:
  /// no `MANAGE_ROLES`, a role an integration owns, or a role at or above the
  /// account's own highest. The owner is exempt from the last one only.
  bool canEditRole(CommunityRole role) {
    if (role.spaceId != spaceId) return false;
    if (!canManageRoles) return false;
    if (isOwner) return true;
    final highest = highestRolePosition;
    return highest != null && role.position < highest;
  }

  /// Whether the account may delete [role]. `@everyone` cannot be deleted by
  /// anybody, owner included.
  bool canDeleteRole(CommunityRole role) =>
      !role.isEveryone && canEditRole(role);

  /// Whether the account outranks [memberId] and may therefore kick, ban or
  /// otherwise act on them.
  ///
  /// Answers false for the account itself and for the guild owner: Discord
  /// refuses both, and offering a ban button that removes nobody is worse than
  /// not offering one.
  bool outranks(String memberId) {
    if (memberId == _permissions._memberId) return false;
    final space = _permissions._workspace.spaces
        .where((item) => item.id == spaceId)
        .firstOrNull;
    if (space?.ownerId == memberId) return false;
    if (isOwner) return true;
    final highest = highestRolePosition;
    if (highest == null) return false;
    return highest > _highestRoleOf(memberId);
  }

  bool canBan(String memberId) => canBanMembers && outranks(memberId);
  bool canKick(String memberId) => canKickMembers && outranks(memberId);

  int _highestRoleOf(String memberId) {
    final membership = _permissions._workspace
        .memberOrNull(memberId)
        ?.membershipIn(spaceId);
    // A member this client holds no record for is treated as outranking
    // nobody's superior — the roster is paged and an absent record means "not
    // loaded", not "has no roles". Guessing high would hide a legitimate ban;
    // guessing low is caught by the server, which is the authority anyway.
    if (membership == null) return 0;
    final held = membership.roleIds.toSet();
    var highest = 0;
    for (final role in _permissions._workspace.roles) {
      if (role.spaceId != spaceId) continue;
      if (!held.contains(role.id)) continue;
      if (role.position > highest) highest = role.position;
    }
    return highest;
  }

  bool _has(BigInt permission) =>
      _bits != null && DiscordPermissions.hasAll(_bits, permission);
}
