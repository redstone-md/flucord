part of 'guild_settings_controller.dart';

/// The AutoMod page's writes.
///
/// Every one of them re-reads nothing: the routes answer with the rule they
/// changed, so the list is patched in place. A rule is a small object and the
/// list is short — Discord caps a guild at a handful of rules per trigger —
/// so there is no page to lose by not refetching.
extension GuildSettingsControllerAutoMod on GuildSettingsController {
  /// Whether the account may change AutoMod at all.
  bool get canEditAutoMod => _capabilities.canManageGuild;

  /// The triggers a new rule may still use.
  ///
  /// Discord allows many keyword rules but exactly one of each of the others,
  /// and refuses a second with an error the form cannot pre-empt otherwise.
  List<AutoModTriggerType> get availableAutoModTriggers => [
    for (final trigger in AutoModTriggerType.values)
      if (trigger != AutoModTriggerType.unknown &&
          (trigger.allowsMany ||
              !_automodRules.any((rule) => rule.triggerType == trigger)))
        trigger,
  ];

  Future<bool> createAutoModRule(
    AutoModRuleDraft draft, {
    String? reason,
  }) async {
    if (!canEditAutoMod || !draft.isValid) return false;
    return _run(() async {
      final created = await _repository.createAutoModRule(
        guildId: guildId,
        draft: draft,
        reason: reason,
      );
      _automodRules = [..._automodRules, created];
    });
  }

  Future<bool> updateAutoModRule(
    String ruleId,
    AutoModRuleEdit edit, {
    String? reason,
  }) async {
    if (!canEditAutoMod || edit.isEmpty) return false;
    return _run(() async {
      final updated = await _repository.updateAutoModRule(
        guildId: guildId,
        ruleId: ruleId,
        edit: edit,
        reason: reason,
      );
      _automodRules = [
        for (final rule in _automodRules)
          if (rule.id == ruleId) updated else rule,
      ];
    });
  }

  /// Switches a rule on or off without touching anything else about it.
  Future<bool> setAutoModRuleEnabled(String ruleId, {required bool enabled}) {
    final edit = AutoModRuleEdit()..enabled = enabled;
    return updateAutoModRule(ruleId, edit);
  }

  Future<bool> deleteAutoModRule(String ruleId, {String? reason}) async {
    if (!canEditAutoMod) return false;
    return _run(() async {
      await _repository.deleteAutoModRule(
        guildId: guildId,
        ruleId: ruleId,
        reason: reason,
      );
      _automodRules = [
        for (final rule in _automodRules)
          if (rule.id != ruleId) rule,
      ];
    });
  }

  /// Asks the server whether a draft would be accepted.
  ///
  /// Deliberately outside [_run]: this runs while the moderator types, and
  /// blocking the window's single write slot on it would make a validation in
  /// flight refuse the save the moderator then asks for. A failure to reach
  /// the server answers "no opinion" rather than "invalid", because refusing a
  /// correct rule over a dropped request would be the worse mistake.
  Future<String?> validateAutoModDraft(AutoModRuleDraft draft) async {
    if (!canEditAutoMod) return null;
    try {
      return await _repository.validateAutoModRule(
        guildId: guildId,
        draft: draft,
      );
    } on Object {
      return null;
    }
  }

  /// Ends the mention-raid alert the guild is under.
  Future<bool> clearMentionRaid() async {
    if (!canEditAutoMod) return false;
    return _run(() => _repository.clearMentionRaid(guildId));
  }

  /// Tells Discord the raid it flagged was not one.
  Future<bool> reportMentionRaidFalseAlarm() async {
    if (!canEditAutoMod) return false;
    return _run(() => _repository.reportMentionRaidFalseAlarm(guildId));
  }
}
