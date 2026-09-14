import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/automod_rule_editing.dart';

/// The AutoMod half of the guild-administration fake.
///
/// A mixin rather than part of the fixture file only because the fixture would
/// otherwise run past the file-length limit. It owns its own state, so the
/// only thing it needs back is the call log.
mixin FakeAutoModRoutes {
  /// The guild the seeded rule belongs to. Set by the fixture, which owns the
  /// id every other fake row uses.
  String get automodGuildId;

  /// What `validateAutoModRule` answers; null means the draft is acceptable.
  String? validationFailure;

  AutoModRuleEdit? lastAutoModEdit;

  late final Map<String, AutoModRule> automodRules = {
    'rule-1': AutoModRule(
      id: 'rule-1',
      guildId: automodGuildId,
      name: 'No invites',
      eventType: AutoModEventType.messageSend,
      triggerType: AutoModTriggerType.keyword,
      metadata: const AutoModTriggerMetadata(keywordFilter: ['discord.gg/*']),
      actions: const [AutoModAction(type: AutoModActionType.blockMessage)],
      enabled: true,
    ),
  };

  /// Records the call and raises whatever the fixture was told to raise.
  void recordAutoModCall(String call);

  Future<List<AutoModRule>> loadAutoModRules(String id) async {
    recordAutoModCall('loadAutoModRules');
    return [
      for (final rule in automodRules.values)
        if (rule.guildId == id) rule,
    ];
  }

  Future<AutoModRule> createAutoModRule({
    required String guildId,
    required AutoModRuleDraft draft,
    String? reason,
  }) async {
    recordAutoModCall('createAutoModRule');
    final rule = AutoModRule(
      id: 'rule-${automodRules.length + 1}',
      guildId: guildId,
      name: draft.name,
      eventType: draft.eventType,
      triggerType: draft.triggerType,
      metadata: draft.metadata,
      actions: draft.actions,
      enabled: draft.enabled,
      exemptRoleIds: draft.exemptRoleIds,
      exemptChannelIds: draft.exemptChannelIds,
    );
    automodRules[rule.id] = rule;
    return rule;
  }

  Future<AutoModRule> updateAutoModRule({
    required String guildId,
    required String ruleId,
    required AutoModRuleEdit edit,
    String? reason,
  }) async {
    recordAutoModCall('updateAutoModRule');
    lastAutoModEdit = edit;
    final existing = automodRules[ruleId]!;
    final updated = AutoModRule(
      id: existing.id,
      guildId: existing.guildId,
      name: edit['name'] as String? ?? existing.name,
      eventType: existing.eventType,
      triggerType: existing.triggerType,
      metadata: existing.metadata,
      actions: existing.actions,
      enabled: edit['enabled'] as bool? ?? existing.enabled,
      exemptRoleIds: existing.exemptRoleIds,
      exemptChannelIds: existing.exemptChannelIds,
    );
    automodRules[ruleId] = updated;
    return updated;
  }

  Future<void> deleteAutoModRule({
    required String guildId,
    required String ruleId,
    String? reason,
  }) async {
    recordAutoModCall('deleteAutoModRule');
    automodRules.remove(ruleId);
  }

  Future<String?> validateAutoModRule({
    required String guildId,
    required AutoModRuleDraft draft,
  }) async {
    recordAutoModCall('validateAutoModRule');
    return validationFailure;
  }

  Future<void> clearMentionRaid(String id) async =>
      recordAutoModCall('clearMentionRaid');

  Future<void> reportMentionRaidFalseAlarm(String id) async =>
      recordAutoModCall('reportMentionRaidFalseAlarm');
}
