part of 'discord_guild_management_repository.dart';

/// Bans, kicks, invites and the audit log.
mixin _DiscordGuildModeration {
  DiscordRestClient get _rest;

  /// Discord's own page size for the ban list, and its hard ceiling.
  static const _banPageLimit = 1000;

  /// The ceiling on `GET /guilds/{id}/bans/search`.
  static const _banSearchLimit = 1000;

  Future<List<GuildBan>> loadBans({
    required String guildId,
    int limit = _banPageLimit,
    String? after,
  }) async => DiscordGuildAdminMapper.bans(
    await _rest.getList(
      '/guilds/${_segment(guildId)}/bans',
      // Clamped rather than forwarded: `limit` reaches here from a caller that
      // may have computed it, and an unbounded page size is a request for the
      // server to hand back as much memory as it feels like.
      query: {'limit': limit.clamp(1, _banPageLimit), 'after': after},
    ),
  );

  Future<List<GuildBan>> searchBans({
    required String guildId,
    required String query,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    return DiscordGuildAdminMapper.bans(
      await _rest.getList(
        '/guilds/${_segment(guildId)}/bans/search',
        query: {
          'limit': limit.clamp(1, _banSearchLimit),
          // A blank query is dropped, matching the renderer: the route reads it
          // as "match everything", which is the ban list, not a search.
          'query': trimmed.isEmpty ? null : trimmed,
        },
      ),
    );
  }

  /// One ban, or several through the bulk route.
  ///
  /// The reason is a header on both, never a body field. A single ban answers
  /// no body at all, so its result is synthesised — a caller should not have to
  /// know which route ran to find out who was banned.
  Future<BulkBanResult> banMembers({
    required String guildId,
    required BanRequest request,
  }) async {
    if (request.userIds.isEmpty) return const BulkBanResult();
    if (!request.isBulk) {
      final userId = request.userIds.single;
      await _rest.requestEmpty(
        'PUT',
        '/guilds/${_segment(guildId)}/bans/${_segment(userId)}',
        body: request.toSingleJson(),
        auditLogReason: request.reason,
      );
      return BulkBanResult(bannedUserIds: [userId]);
    }
    return DiscordGuildAdminMapper.bulkBanResult(
      await _rest.requestObject(
        'POST',
        '/guilds/${_segment(guildId)}/bulk-ban',
        body: request.toBulkJson(),
        auditLogReason: request.reason,
      ),
    );
  }

  Future<void> unbanMember({
    required String guildId,
    required String userId,
    String? reason,
  }) => _rest.requestEmpty(
    'DELETE',
    '/guilds/${_segment(guildId)}/bans/${_segment(userId)}',
    auditLogReason: reason,
  );

  /// Kick is the one moderation route whose reason is a **query parameter**
  /// rather than the `X-Audit-Log-Reason` header. Sending it as a header here
  /// costs the audit-log entry its reason and nothing complains.
  Future<void> kickMember({
    required String guildId,
    required String userId,
    String? reason,
  }) {
    final trimmed = reason?.trim();
    return _rest.requestEmpty(
      'DELETE',
      '/guilds/${_segment(guildId)}/members/${_segment(userId)}',
      query: {'reason': trimmed == null || trimmed.isEmpty ? null : trimmed},
    );
  }

  Future<List<GuildInvite>> loadGuildInvites(String guildId) async =>
      DiscordGuildAdminMapper.invites(
        await _rest.getList('/guilds/${_segment(guildId)}/invites'),
      );

  Future<GuildInvite> createChannelInvite({
    required String channelId,
    InviteOptions options = const InviteOptions(),
  }) async {
    final payload = await _rest.requestObject(
      'POST',
      '/channels/${_segment(channelId)}/invites',
      body: options.toJson(),
    );
    final invite = DiscordGuildAdminMapper.invite(payload);
    if (invite == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Invite response carried no code',
      );
    }
    return invite;
  }

  Future<void> revokeInvite(String code) =>
      _rest.requestEmpty('DELETE', '/invites/${_segment(code)}');

  Future<AuditLogPage> loadAuditLog({
    required String guildId,
    AuditLogQuery query = const AuditLogQuery(),
  }) async => DiscordGuildAdminMapper.auditLog(
    await _rest.requestObject(
      'GET',
      '/guilds/${_segment(guildId)}/audit-logs',
      query: query.toQueryParameters(),
    ),
  );
}
