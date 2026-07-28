part of 'discord_guild_management_repository.dart';

/// AutoMod rules, and the two raid controls that sit beside them.
mixin _DiscordGuildAutoMod {
  DiscordRestClient get _rest;

  String _automodBase(String guildId) =>
      '/guilds/${_segment(guildId)}/auto-moderation';

  Future<List<AutoModRule>> loadAutoModRules(String guildId) async =>
      DiscordAutoModMapper.rules(
        await _rest.getList('${_automodBase(guildId)}/rules'),
        guildId: guildId,
      );

  Future<AutoModRule> createAutoModRule({
    required String guildId,
    required AutoModRuleDraft draft,
    String? reason,
  }) async => _required(
    await _rest.requestObject(
      'POST',
      '${_automodBase(guildId)}/rules',
      body: AutoModRuleEdit.encodeDraft(draft),
      auditLogReason: reason,
    ),
    guildId,
  );

  Future<AutoModRule> updateAutoModRule({
    required String guildId,
    required String ruleId,
    required AutoModRuleEdit edit,
    String? reason,
  }) async => _required(
    await _rest.requestObject(
      'PATCH',
      '${_automodBase(guildId)}/rules/${_segment(ruleId)}',
      body: edit.toJson(),
      auditLogReason: reason,
    ),
    guildId,
  );

  Future<void> deleteAutoModRule({
    required String guildId,
    required String ruleId,
    String? reason,
  }) => _rest.requestEmpty(
    'DELETE',
    '${_automodBase(guildId)}/rules/${_segment(ruleId)}',
    auditLogReason: reason,
  );

  /// Asks the server whether a draft is acceptable without creating it.
  ///
  /// Discord's own page calls this while the moderator types, because a regex
  /// is compiled server-side and the only honest way to know it is valid is to
  /// ask. Returns the failure text, or null when the draft would be accepted.
  Future<String?> validateAutoModRule({
    required String guildId,
    required AutoModRuleDraft draft,
  }) async {
    try {
      await _rest.requestObject(
        'POST',
        '${_automodBase(guildId)}/rules/validate',
        body: AutoModRuleEdit.encodeDraft(draft),
      );
      return null;
    } on DiscordApiException catch (error) {
      // A refusal is the answer, not a failure. Anything that is not the
      // server saying "no" — a dropped connection, a rate limit — is still an
      // error, because reporting it as "your regex is wrong" would be a lie.
      if (error.statusCode != 400) rethrow;
      return error.message;
    }
  }

  /// Ends a mention-raid alert the guild is currently under.
  Future<void> clearMentionRaid(String guildId) =>
      _rest.requestEmpty('POST', '${_automodBase(guildId)}/clear-mention-raid');

  /// Tells Discord the raid it flagged was not one.
  Future<void> reportMentionRaidFalseAlarm(String guildId) =>
      _rest.requestEmpty('POST', '${_automodBase(guildId)}/false-alarm');

  AutoModRule _required(Map<String, Object?> payload, String guildId) {
    final rule = DiscordAutoModMapper.rule(payload, fallbackGuildId: guildId);
    if (rule == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'AutoMod rule response carried no id',
      );
    }
    return rule;
  }
}
