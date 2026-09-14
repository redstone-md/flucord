part of 'discord_guild_management_repository.dart';

/// The per-member routes the member popover drives.
///
/// Nickname and timeout are one partial patch route; roles have a route of
/// their own per role, which is what keeps two moderators ticking two boxes
/// from erasing each other's work.
mixin _DiscordGuildMemberAdministration {
  DiscordRestClient get _rest;

  String _memberBase(String guildId, String userId) =>
      '/guilds/${_segment(guildId)}/members/${_segment(userId)}';

  /// `GET /guilds/{id}/members/{userId}`.
  ///
  /// The route answers `404` for a member the guild has since lost, which is
  /// the server saying the popover is stale; that failure is the caller's to
  /// show rather than something to swallow into an empty record.
  Future<GuildMemberProfile> loadMember({
    required String guildId,
    required String userId,
  }) async => DiscordGuildAdminMapper.memberProfile(
    await _rest.getObject(_memberBase(guildId, userId)),
    guildId: guildId,
    userId: userId,
  );

  /// `PATCH /guilds/{id}/members/{userId}` with only the fields the edit set.
  Future<GuildMemberProfile> updateMember({
    required String guildId,
    required String userId,
    required GuildMemberEdit edit,
    String? reason,
  }) async => DiscordGuildAdminMapper.memberProfile(
    await _rest.requestObject(
      'PATCH',
      _memberBase(guildId, userId),
      body: edit.toJson(),
      auditLogReason: reason,
    ),
    guildId: guildId,
    userId: userId,
  );

  Future<void> grantMemberRole({
    required String guildId,
    required String userId,
    required String roleId,
    String? reason,
  }) => _rest.requestEmpty(
    'PUT',
    '${_memberBase(guildId, userId)}/roles/${_segment(roleId)}',
    auditLogReason: reason,
  );

  Future<void> revokeMemberRole({
    required String guildId,
    required String userId,
    required String roleId,
    String? reason,
  }) => _rest.requestEmpty(
    'DELETE',
    '${_memberBase(guildId, userId)}/roles/${_segment(roleId)}',
    auditLogReason: reason,
  );
}
