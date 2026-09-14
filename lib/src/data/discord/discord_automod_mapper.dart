import '../../domain/automod_rule.dart';

/// Reads the AutoMod rule objects `/guilds/{id}/auto-moderation/rules` returns.
///
/// Every enum falls back to `unknown` rather than throwing. Discord ships new
/// trigger and action types to its own client before third parties hear about
/// them, and a settings page that failed to open because one rule in the list
/// used a trigger this build predates would be worse than one row reading
/// "unsupported".
abstract final class DiscordAutoModMapper {
  static List<AutoModRule> rules(Object? payload, {String? guildId}) => [
    for (final raw in _list(payload))
      if (raw is Map)
        ?rule(raw.cast<String, Object?>(), fallbackGuildId: guildId),
  ];

  /// Maps one rule, or null when it carries no id — which is what a create
  /// that the server refused without erroring looks like.
  static AutoModRule? rule(
    Map<String, Object?> payload, {
    String? fallbackGuildId,
  }) {
    final id = _string(payload['id']);
    if (id == null) return null;
    return AutoModRule(
      id: id,
      guildId: _string(payload['guild_id']) ?? fallbackGuildId ?? '',
      name: _string(payload['name']) ?? '',
      creatorId: _string(payload['creator_id']) ?? '',
      eventType: AutoModEventType.fromCode(_int(payload['event_type']) ?? 0),
      triggerType: AutoModTriggerType.fromCode(
        _int(payload['trigger_type']) ?? 0,
      ),
      metadata: metadata(payload['trigger_metadata']),
      actions: actions(payload['actions']),
      // Absent means enabled: Discord omits the flag on a rule that has never
      // been switched off.
      enabled: payload['enabled'] is bool ? payload['enabled']! as bool : true,
      exemptRoleIds: _ids(payload['exempt_roles']),
      exemptChannelIds: _ids(payload['exempt_channels']),
    );
  }

  static AutoModTriggerMetadata metadata(Object? payload) {
    if (payload is! Map) return const AutoModTriggerMetadata();
    final data = payload.cast<String, Object?>();
    return AutoModTriggerMetadata(
      keywordFilter: _strings(data['keyword_filter']),
      regexPatterns: _strings(data['regex_patterns']),
      presets: [
        for (final raw in _list(data['presets']))
          if (_int(raw) case final int code)
            AutoModKeywordPreset.fromCode(code),
      ],
      allowList: _strings(data['allow_list']),
      mentionTotalLimit: _int(data['mention_total_limit']) ?? 0,
      mentionRaidProtectionEnabled:
          data['mention_raid_protection_enabled'] == true,
    );
  }

  static List<AutoModAction> actions(Object? payload) => [
    for (final raw in _list(payload))
      if (raw is Map) action(raw.cast<String, Object?>()),
  ];

  static AutoModAction action(Map<String, Object?> payload) {
    final metadata = payload['metadata'] is Map
        ? (payload['metadata']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return AutoModAction(
      type: AutoModActionType.fromCode(_int(payload['type']) ?? 0),
      channelId: _string(metadata['channel_id']) ?? '',
      durationSeconds: _int(metadata['duration_seconds']) ?? 0,
      customMessage: _string(metadata['custom_message']) ?? '',
    );
  }

  static List<String> _strings(Object? value) => [
    for (final raw in _list(value))
      if (raw is String) raw,
  ];

  static List<String> _ids(Object? value) => [
    for (final raw in _list(value))
      if (_string(raw) case final String id) id,
  ];

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  static int? _int(Object? value) => switch (value) {
    final int raw => raw,
    final String raw => int.tryParse(raw),
    _ => null,
  };
}
