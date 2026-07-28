import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/automod_rule.dart';
import '../../domain/chat_models.dart';
import 'guild_automod_rule_dialog.dart';
import 'guild_automod_rule_fields.dart';
import 'guild_settings_controls.dart';

/// The AutoMod page: which rules the server runs, and what each one does.
///
/// A rule is switched off rather than deleted wherever there is a choice.
/// Deleting is how a moderator loses a word list they spent an afternoon on,
/// and Discord's own page leads with the same switch.
class GuildSettingsAutoModSection extends StatelessWidget {
  const GuildSettingsAutoModSection({
    required this.controller,
    required this.workspace,
    required this.spaceId,
    super.key,
  });

  final GuildSettingsController controller;
  final ChatWorkspace workspace;
  final String spaceId;

  @override
  Widget build(BuildContext context) {
    final rules = controller.automodRules;
    return GuildSettingsPanel(
      title: 'AutoMod',
      subtitle: 'Rules the server applies before a message is posted.',
      trailing: FilledButton.tonal(
        key: const ValueKey('automod-create-open'),
        onPressed:
            controller.isBusy || controller.availableAutoModTriggers.isEmpty
            ? null
            : () => unawaited(_openRuleDialog(context)),
        child: const Text('Add rule'),
      ),
      children: [
        GuildSettingsActionError(error: controller.actionError),
        if (rules.isEmpty)
          const GuildSettingsEmpty(message: 'No rules are set up here.')
        else
          for (final rule in rules)
            GuildSettingsRow(
              key: ValueKey('automod-rule-${rule.id}'),
              leading: Icon(_iconFor(rule.triggerType), size: 16),
              title: rule.name,
              subtitle: describeAutoModRule(rule, workspace: workspace),
              // Compact on purpose: three controls at their default tap size
              // overflow the row once the window is narrow enough to drop the
              // navigation rail.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    key: ValueKey('automod-enabled-${rule.id}'),
                    value: rule.enabled,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: controller.isBusy
                        ? null
                        : (value) => unawaited(
                            controller.setAutoModRuleEnabled(
                              rule.id,
                              enabled: value,
                            ),
                          ),
                  ),
                  _CompactIcon(
                    buttonKey: ValueKey('automod-edit-${rule.id}'),
                    tooltip: 'Edit',
                    icon: Icons.edit_outlined,
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(_openRuleDialog(context, rule: rule)),
                  ),
                  _CompactIcon(
                    buttonKey: ValueKey('automod-delete-${rule.id}'),
                    tooltip: 'Delete',
                    icon: Icons.delete_outline,
                    onPressed: controller.isBusy
                        ? null
                        : () =>
                              unawaited(controller.deleteAutoModRule(rule.id)),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 18),
        _RaidControls(controller: controller),
      ],
    );
  }

  Future<void> _openRuleDialog(
    BuildContext context, {
    AutoModRule? rule,
  }) async {
    final channels = [
      for (final channel in workspace.channels)
        if (channel.spaceId == spaceId && channel.kind == ChannelKind.text)
          channel,
    ];
    final result = await showDialog<AutoModRuleDialogResult>(
      context: context,
      builder: (_) => GuildAutoModRuleDialog(
        rule: rule,
        channels: [
          for (final channel in channels)
            AutoModExemptTarget(id: channel.id, label: '#${channel.name}'),
        ],
        // From the workspace rather than from the settings window's roles
        // page: that page loads only when it is opened, and a rule cannot
        // offer an exemption for a role nobody fetched.
        roles: [
          for (final role in workspace.roles)
            if (role.spaceId == spaceId)
              AutoModExemptTarget(id: role.id, label: role.name),
        ],
        availableTriggers: controller.availableAutoModTriggers,
        validate: controller.validateAutoModDraft,
      ),
    );
    if (result == null) return;
    if (result.edit case final edit? when rule != null) {
      await controller.updateAutoModRule(rule.id, edit);
      return;
    }
    if (result.draft case final draft?) {
      await controller.createAutoModRule(draft);
    }
  }

  static IconData _iconFor(AutoModTriggerType trigger) => switch (trigger) {
    AutoModTriggerType.keyword => Icons.abc,
    AutoModTriggerType.spamLink => Icons.link_off,
    AutoModTriggerType.mlSpam => Icons.filter_alt_outlined,
    AutoModTriggerType.defaultKeywordList => Icons.playlist_remove,
    AutoModTriggerType.mentionSpam => Icons.alternate_email,
    AutoModTriggerType.userProfile => Icons.badge_outlined,
    AutoModTriggerType.serverPolicy => Icons.policy_outlined,
    AutoModTriggerType.unknown => Icons.help_outline,
  };
}

/// An icon button sized to fit three controls in one row.
class _CompactIcon extends StatelessWidget {
  const _CompactIcon({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    tooltip: tooltip,
    icon: Icon(icon, size: 16),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    onPressed: onPressed,
  );
}

/// One line saying what the rule watches and what it does about it.
String describeAutoModRule(AutoModRule rule, {ChatWorkspace? workspace}) {
  final watches = switch (rule.triggerType) {
    AutoModTriggerType.keyword ||
    AutoModTriggerType.userProfile => _countWords(rule),
    AutoModTriggerType.spamLink => 'Suspicious links',
    AutoModTriggerType.mlSpam => 'Spam Discord detects',
    AutoModTriggerType.defaultKeywordList => "Discord's word lists",
    AutoModTriggerType.mentionSpam =>
      'Over ${rule.metadata.mentionTotalLimit} mentions',
    AutoModTriggerType.serverPolicy => 'Server policy',
    AutoModTriggerType.unknown => 'A rule this build does not know',
  };
  final consequences = <String>[
    if (rule.blocksMessages) 'blocks the message',
    if (rule.alertChannelId.isNotEmpty)
      'alerts ${_channelName(rule.alertChannelId, workspace)}',
    if (rule.timeout > Duration.zero)
      'times out for ${_describeTimeout(rule.timeout)}',
  ];
  if (consequences.isEmpty) return '$watches — no action';
  return '$watches — ${consequences.join(', ')}';
}

String _countWords(AutoModRule rule) {
  final words = rule.metadata.keywordFilter.length;
  final patterns = rule.metadata.regexPatterns.length;
  final parts = <String>[
    if (words > 0) '$words word${words == 1 ? '' : 's'}',
    if (patterns > 0) '$patterns pattern${patterns == 1 ? '' : 's'}',
  ];
  return parts.isEmpty ? 'Nothing yet' : parts.join(' and ');
}

String _channelName(String channelId, ChatWorkspace? workspace) {
  if (workspace == null) return 'a channel';
  for (final channel in workspace.channels) {
    if (channel.id == channelId) return '#${channel.name}';
  }
  return 'a channel';
}

String _describeTimeout(Duration timeout) {
  if (timeout.inDays > 0) {
    return '${timeout.inDays} day${timeout.inDays == 1 ? '' : 's'}';
  }
  if (timeout.inHours > 0) {
    return '${timeout.inHours} hour${timeout.inHours == 1 ? '' : 's'}';
  }
  return '${timeout.inMinutes} minute${timeout.inMinutes == 1 ? '' : 's'}';
}

/// The two controls that only mean anything while a raid is in progress.
class _RaidControls extends StatelessWidget {
  const _RaidControls({required this.controller});

  final GuildSettingsController controller;

  // A Wrap rather than a Row: the two buttons plus their label do not fit
  // side by side once the window is narrow enough to drop the navigation
  // rail, and a label that wraps above them reads better than one that is
  // ellipsised down to nothing.
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      Text('Raid alerts', style: Theme.of(context).textTheme.titleSmall),
      TextButton(
        key: const ValueKey('automod-false-alarm'),
        onPressed: controller.isBusy
            ? null
            : () => unawaited(controller.reportMentionRaidFalseAlarm()),
        child: const Text('Not a raid'),
      ),
      FilledButton.tonal(
        key: const ValueKey('automod-clear-raid'),
        onPressed: controller.isBusy
            ? null
            : () => unawaited(controller.clearMentionRaid()),
        child: const Text('Clear alert'),
      ),
    ],
  );
}
