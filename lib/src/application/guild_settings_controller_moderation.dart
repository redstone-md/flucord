part of 'guild_settings_controller.dart';

extension GuildSettingsControllerModeration on GuildSettingsController {
  /// Bans one member or a selection of them.
  ///
  /// The hierarchy check runs per user rather than once for the batch: a bulk
  /// ban that included one member the moderator does not outrank would be
  /// partly applied by the server and wholly confusing here, so those are
  /// dropped before the request instead.
  Future<bool> banMembers(BanRequest request) async {
    if (!_capabilities.canBanMembers) return false;
    final permitted = [
      for (final userId in request.userIds)
        if (_capabilities.canBan(userId)) userId,
    ];
    if (permitted.isEmpty) return false;
    final scoped = BanRequest(
      userIds: permitted,
      deletion: request.deletion,
      reason: request.reason,
      moderatorReportId: request.moderatorReportId,
    );
    return _run(() async {
      await _repository.banMembers(guildId: guildId, request: scoped);
      // The ban list is a page of server state, not something to patch locally:
      // the response names who was banned but not their user record, and a row
      // built from the id alone would render as a blank name.
      _loaded.remove(GuildSettingsSection.bans);
    });
  }

  Future<bool> unbanMember(String userId, {String? reason}) async {
    if (!_capabilities.canBanMembers) return false;
    return _run(() async {
      await _repository.unbanMember(
        guildId: guildId,
        userId: userId,
        reason: reason,
      );
      _bans = [
        for (final ban in _bans)
          if (ban.userId != userId) ban,
      ];
    });
  }

  Future<bool> kickMember(String userId, {String? reason}) async {
    if (!_capabilities.canKick(userId)) return false;
    return _run(
      () => _repository.kickMember(
        guildId: guildId,
        userId: userId,
        reason: reason,
      ),
    );
  }

  /// Searches the ban list server-side. A blank query restores the first page.
  Future<void> searchBans(String query) async {
    if (!_capabilities.canBanMembers) return;
    _loading.add(GuildSettingsSection.bans);
    _errors.remove(GuildSettingsSection.bans);
    _notify();
    try {
      final trimmed = query.trim();
      _bans = trimmed.isEmpty
          ? await _repository.loadBans(guildId: guildId)
          : await _repository.searchBans(guildId: guildId, query: trimmed);
      _loaded.add(GuildSettingsSection.bans);
    } on Object catch (error) {
      _errors[GuildSettingsSection.bans] = error;
    } finally {
      _loading.remove(GuildSettingsSection.bans);
      _notify();
    }
  }

  /// Creates an invite to [channelId].
  ///
  /// Gated on `CREATE_INSTANT_INVITE` rather than `MANAGE_GUILD`: making an
  /// invite is an ordinary member's power, and only revoking one is a
  /// moderator's.
  Future<GuildInvite?> createInvite({
    required String channelId,
    InviteOptions options = const InviteOptions(),
  }) async {
    if (!_capabilities.canCreateInvite) return null;
    GuildInvite? created;
    await _run(() async {
      created = await _repository.createChannelInvite(
        channelId: channelId,
        options: options,
      );
      _invites = [
        ...(created == null ? _invites : [created!, ..._invites]),
      ];
    });
    return created;
  }

  Future<bool> revokeInvite(String code) async {
    if (!_capabilities.canManageGuild) return false;
    return _run(() async {
      await _repository.revokeInvite(code);
      _invites = [
        for (final invite in _invites)
          if (invite.code != code) invite,
      ];
    });
  }

  /// Replaces the audit-log filter and refetches from the top.
  ///
  /// The two filters are exclusive, as they are in Discord's own log: the
  /// action call passes only an action and the actor call only an actor. The
  /// server does accept both, but the renderer never sends both, and a filter
  /// combination nobody has ever exercised is not the place to find out — so a
  /// caller that supplies both gets the narrower one, the actor.
  Future<void> filterAuditLog({
    AuditLogActionType? action,
    String? userId,
  }) async {
    if (!_capabilities.canViewAuditLog) return;
    _auditQuery = AuditLogQuery(
      action: userId == null ? action : null,
      userId: userId,
    );
    _loading.add(GuildSettingsSection.auditLog);
    _errors.remove(GuildSettingsSection.auditLog);
    _notify();
    try {
      await _fetchAuditPage(_auditQuery, append: false);
      _loaded.add(GuildSettingsSection.auditLog);
    } on Object catch (error) {
      _errors[GuildSettingsSection.auditLog] = error;
    } finally {
      _loading.remove(GuildSettingsSection.auditLog);
      _notify();
    }
  }

  /// Fetches the page before the oldest entry currently held.
  Future<void> loadMoreAuditEntries() async {
    if (!_capabilities.canViewAuditLog) return;
    if (!_hasOlderAuditEntries) return;
    if (_loading.contains(GuildSettingsSection.auditLog)) return;
    final oldest = _auditRecords.isEmpty
        ? null
        : _auditRecords.last.entries.last.id;
    if (oldest == null) return;
    _loading.add(GuildSettingsSection.auditLog);
    _notify();
    try {
      await _fetchAuditPage(_auditQuery.pageAfter(oldest), append: true);
    } on Object catch (error) {
      _errors[GuildSettingsSection.auditLog] = error;
    } finally {
      _loading.remove(GuildSettingsSection.auditLog);
      _notify();
    }
  }

  Future<void> _fetchAuditPage(
    AuditLogQuery query, {
    required bool append,
  }) async {
    final page = await _repository.loadAuditLog(guildId: guildId, query: query);
    final merged = AuditLogMerge.apply(page.entries);
    _auditRecords = append ? [..._auditRecords, ...merged] : merged;
    _auditUserNames = append
        ? {..._auditUserNames, ...page.userNames}
        : page.userNames;
    _hasOlderAuditEntries = page.hasOlderEntries;
  }
}
