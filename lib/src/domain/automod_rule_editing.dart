import 'automod_rule.dart';

/// `POST /guilds/{id}/auto-moderation/rules`.
///
/// A create is a whole rule rather than a patch, so this states every field
/// the server needs and nothing is optional-by-omission: a rule created
/// without actions would exist, run, and do nothing.
final class AutoModRuleDraft {
  const AutoModRuleDraft({
    required this.name,
    required this.eventType,
    required this.triggerType,
    required this.actions,
    this.metadata = const AutoModTriggerMetadata(),
    this.enabled = true,
    this.exemptRoleIds = const [],
    this.exemptChannelIds = const [],
  });

  final String name;
  final AutoModEventType eventType;
  final AutoModTriggerType triggerType;
  final AutoModTriggerMetadata metadata;
  final List<AutoModAction> actions;
  final bool enabled;
  final List<String> exemptRoleIds;
  final List<String> exemptChannelIds;

  /// Whether the server would refuse this outright.
  ///
  /// Checked here rather than only in the form because the same draft reaches
  /// the server from the create dialog and from a duplicated rule, and the
  /// second path has no form to check it.
  bool get isValid {
    if (name.trim().isEmpty || actions.isEmpty) return false;
    if (eventType == AutoModEventType.unknown) return false;
    if (triggerType == AutoModTriggerType.unknown) return false;
    return switch (triggerType) {
      AutoModTriggerType.keyword || AutoModTriggerType.userProfile =>
        metadata.keywordFilter.isNotEmpty || metadata.regexPatterns.isNotEmpty,
      AutoModTriggerType.defaultKeywordList => metadata.presets.isNotEmpty,
      AutoModTriggerType.mentionSpam => metadata.mentionTotalLimit > 0,
      _ => true,
    };
  }
}

/// `PATCH /guilds/{id}/auto-moderation/rules/{rule}`.
///
/// Only what was touched is sent. Discord replaces a list field wholesale, so
/// setting keywords means sending all of them — which is why the setters take
/// the finished list rather than offering add and remove.
final class AutoModRuleEdit {
  AutoModRuleEdit();

  final Map<String, Object?> _values = {};

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;
  Iterable<String> get keys => _values.keys;
  Object? operator [](String key) => _values[key];

  set name(String value) => _values['name'] = value;

  /// Switching a rule off leaves it in place. Discord's page does the same,
  /// because deleting is how a moderator loses a word list by accident.
  set enabled(bool value) => _values['enabled'] = value;

  set eventType(AutoModEventType value) => _values['event_type'] = value.code;

  // There is deliberately no trigger-type setter. Discord refuses to change
  // what a rule triggers on, so a caller wanting a different trigger wants a
  // different rule.

  set metadata(AutoModTriggerMetadata value) =>
      _values['trigger_metadata'] = encodeMetadata(value);

  set actions(List<AutoModAction> value) =>
      _values['actions'] = [for (final action in value) encodeAction(action)];

  set exemptRoleIds(List<String> value) =>
      _values['exempt_roles'] = List<String>.of(value);

  set exemptChannelIds(List<String> value) =>
      _values['exempt_channels'] = List<String>.of(value);

  Map<String, Object?> toJson() => Map.unmodifiable(_values);

  /// Shared with the create path, which sends the same shapes.
  static Map<String, Object?> encodeMetadata(AutoModTriggerMetadata value) => {
    if (value.keywordFilter.isNotEmpty) 'keyword_filter': value.keywordFilter,
    if (value.regexPatterns.isNotEmpty) 'regex_patterns': value.regexPatterns,
    if (value.presets.isNotEmpty)
      'presets': [for (final preset in value.presets) preset.code],
    if (value.allowList.isNotEmpty) 'allow_list': value.allowList,
    if (value.mentionTotalLimit > 0)
      'mention_total_limit': value.mentionTotalLimit,
    if (value.mentionRaidProtectionEnabled)
      'mention_raid_protection_enabled': true,
  };

  static Map<String, Object?> encodeAction(AutoModAction action) => {
    'type': action.type.code,
    // An action with nothing to configure sends an empty object rather than
    // no key: Discord treats a missing metadata object as a malformed action.
    'metadata': {
      if (action.channelId.isNotEmpty) 'channel_id': action.channelId,
      if (action.durationSeconds > 0)
        'duration_seconds': action.durationSeconds,
      if (action.customMessage.isNotEmpty)
        'custom_message': action.customMessage,
    },
  };

  static Map<String, Object?> encodeDraft(AutoModRuleDraft draft) => {
    'name': draft.name,
    'event_type': draft.eventType.code,
    'trigger_type': draft.triggerType.code,
    'trigger_metadata': encodeMetadata(draft.metadata),
    'actions': [for (final action in draft.actions) encodeAction(action)],
    'enabled': draft.enabled,
    'exempt_roles': draft.exemptRoleIds,
    'exempt_channels': draft.exemptChannelIds,
  };
}
