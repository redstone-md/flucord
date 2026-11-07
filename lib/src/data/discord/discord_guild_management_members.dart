part of 'discord_guild_management_repository.dart';

/// The per-member routes the member popover drives.
///
/// Nickname and timeout are one partial patch route; roles have a route of
/// their own per role, which is what keeps two moderators ticking two boxes
/// from erasing each other's work. The `@me` routes are the account's own
/// server profile, which any member may edit.
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

  String _ownBase(String guildId) => '/guilds/${_segment(guildId)}/members/@me';

  /// `GET /users/@me/guilds/{id}/member`, the private member object, which
  /// is the one that carries the server bio and banner.
  Future<OwnServerProfile> loadOwnServerProfile(String guildId) async =>
      DiscordGuildAdminMapper.ownServerProfile(
        await _rest.getObject('/users/@me/guilds/${_segment(guildId)}/member'),
        guildId: guildId,
      );

  /// `PATCH /guilds/{id}/members/@me` with only the touched fields.
  Future<OwnServerProfile> saveOwnServerProfile({
    required String guildId,
    required ServerProfileEdit edit,
  }) async {
    try {
      return DiscordGuildAdminMapper.ownServerProfile(
        await _rest.requestObject(
          'PATCH',
          _ownBase(guildId),
          body: edit.toJson(),
        ),
        guildId: guildId,
      );
    } on DiscordApiException catch (error) {
      if (error.isForbidden) {
        throw const ServerProfileRefusal(
          'This server does not let you change that.',
        );
      }
      if (error.statusCode != 400) rethrow;
      final reason = _firstFieldError(error.responsePayload?['errors']);
      throw ServerProfileRefusal(
        'Discord did not save your server profile: '
        '${reason ?? error.message}',
      );
    }
  }

  /// The first `_errors[].message` in a 50035 answer's error tree, which
  /// names the field that failed, such as a nickname that is too long.
  static String? _firstFieldError(Object? tree) {
    if (tree is! Map) return null;
    if (tree['_errors'] case [{'message': final String message}, ...]) {
      return message;
    }
    for (final child in tree.values) {
      if (_firstFieldError(child) case final message?) return message;
    }
    return null;
  }
}
