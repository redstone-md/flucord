import 'package:flutter/material.dart';

import '../../domain/automod_rule.dart';
import '../../domain/automod_rule_editing.dart';
import 'guild_automod_rule_fields.dart';

/// What the dialog hands back: a draft for a new rule, or an edit for an
/// existing one. Never both — which of the two it is follows from whether the
/// dialog was opened on a rule.
final class AutoModRuleDialogResult {
  const AutoModRuleDialogResult.create(this.draft) : edit = null;
  const AutoModRuleDialogResult.update(this.edit) : draft = null;

  final AutoModRuleDraft? draft;
  final AutoModRuleEdit? edit;
}

/// Creates or edits one AutoMod rule.
///
/// The trigger is chosen once and then fixed: Discord refuses to change what
/// an existing rule matches on, so on an edit the choice is shown as a label
/// rather than as a control that would fail on save.
class GuildAutoModRuleDialog extends StatefulWidget {
  const GuildAutoModRuleDialog({
    required this.channels,
    required this.roles,
    required this.availableTriggers,
    this.rule,
    this.validate,
    super.key,
  });

  final AutoModRule? rule;
  final List<AutoModExemptTarget> channels;
  final List<AutoModExemptTarget> roles;
  final List<AutoModTriggerType> availableTriggers;

  /// Asks the server whether the draft is acceptable. Optional: without it the
  /// dialog simply does not offer server-side validation.
  final Future<String?> Function(AutoModRuleDraft draft)? validate;

  @override
  State<GuildAutoModRuleDialog> createState() => _GuildAutoModRuleDialogState();
}

class _GuildAutoModRuleDialogState extends State<GuildAutoModRuleDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.rule?.name ?? '',
  );
  late final TextEditingController _keywords = TextEditingController(
    text: widget.rule?.metadata.keywordFilter.join(', ') ?? '',
  );
  late final TextEditingController _patterns = TextEditingController(
    text: widget.rule?.metadata.regexPatterns.join(', ') ?? '',
  );
  late final TextEditingController _allowList = TextEditingController(
    text: widget.rule?.metadata.allowList.join(', ') ?? '',
  );
  late final TextEditingController _mentionLimit = TextEditingController(
    text: (widget.rule?.metadata.mentionTotalLimit ?? 0) > 0
        ? '${widget.rule!.metadata.mentionTotalLimit}'
        : '',
  );

  late AutoModTriggerType _trigger =
      widget.rule?.triggerType ??
      (widget.availableTriggers.isEmpty
          ? AutoModTriggerType.keyword
          : widget.availableTriggers.first);
  late bool _blockMessage = widget.rule?.blocksMessages ?? true;
  late String _alertChannelId = widget.rule?.alertChannelId ?? '';
  late Duration _timeout = widget.rule?.timeout ?? Duration.zero;
  late List<AutoModKeywordPreset> _presets = [
    for (final preset in widget.rule?.metadata.presets ?? const [])
      if (preset != AutoModKeywordPreset.unknown) preset,
  ];
  late List<String> _exemptRoleIds = [...?widget.rule?.exemptRoleIds]..sort();
  late List<String> _exemptChannelIds = [...?widget.rule?.exemptChannelIds]
    ..sort();

  String? _serverVerdict;
  bool _checking = false;

  bool get _isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    // Save is offered only for a draft the server would take, and whether it
    // would depends on what is typed. Without this the button stays disabled
    // until some other control happens to rebuild the dialog.
    for (final field in _fields) {
      field.addListener(_onFieldChanged);
    }
  }

  List<TextEditingController> get _fields => [
    _name,
    _keywords,
    _patterns,
    _allowList,
    _mentionLimit,
  ];

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.removeListener(_onFieldChanged);
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('automod-rule-dialog'),
    title: Text(_isEditing ? 'Edit rule' : 'New AutoMod rule'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('automod-name'),
              controller: _name,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Rule name',
              ),
            ),
            const SizedBox(height: 12),
            if (_isEditing)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Trigger: ${autoModTriggerLabel(_trigger)}'),
              )
            else
              DropdownButtonFormField<AutoModTriggerType>(
                key: const ValueKey('automod-trigger'),
                initialValue: _trigger,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Trigger',
                ),
                items: [
                  for (final trigger in widget.availableTriggers)
                    DropdownMenuItem(
                      value: trigger,
                      child: Text(autoModTriggerLabel(trigger)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _trigger = value ?? _trigger),
              ),
            if (_trigger.hasKeywords) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('automod-keywords'),
                controller: _keywords,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Words, comma separated',
                  helperText: 'A leading or trailing * anchors the match.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('automod-patterns'),
                controller: _patterns,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Regular expressions, comma separated',
                ),
              ),
            ],
            if (_trigger == AutoModTriggerType.defaultKeywordList) ...[
              const SizedBox(height: 12),
              AutoModPresetField(
                selected: _presets,
                onChanged: (presets) => setState(() => _presets = presets),
              ),
            ],
            if (_trigger.hasKeywords ||
                _trigger == AutoModTriggerType.defaultKeywordList) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('automod-allow-list'),
                controller: _allowList,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Words to allow anyway, comma separated',
                ),
              ),
            ],
            if (_trigger == AutoModTriggerType.mentionSpam) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('automod-mention-limit'),
                controller: _mentionLimit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Mentions allowed in one message',
                ),
              ),
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              key: const ValueKey('automod-block'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Block the message'),
              value: _blockMessage,
              onChanged: (value) => setState(() => _blockMessage = value),
            ),
            DropdownButtonFormField<String>(
              key: const ValueKey('automod-alert-channel'),
              initialValue: _alertChannelId.isEmpty ? '' : _alertChannelId,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Alert channel',
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('No alerts')),
                for (final channel in widget.channels)
                  DropdownMenuItem(
                    value: channel.id,
                    child: Text(channel.label),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _alertChannelId = value ?? ''),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const ValueKey('automod-timeout'),
              initialValue: _timeout.inSeconds,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Time the member out',
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('No timeout')),
                DropdownMenuItem(value: 60, child: Text('1 minute')),
                DropdownMenuItem(value: 3600, child: Text('1 hour')),
                DropdownMenuItem(value: 86400, child: Text('1 day')),
                DropdownMenuItem(value: 604800, child: Text('1 week')),
              ],
              onChanged: (value) =>
                  setState(() => _timeout = Duration(seconds: value ?? 0)),
            ),
            const SizedBox(height: 16),
            AutoModExemptionField(
              roles: widget.roles,
              channels: widget.channels,
              exemptRoleIds: _exemptRoleIds,
              exemptChannelIds: _exemptChannelIds,
              onRolesChanged: (ids) => setState(() => _exemptRoleIds = ids),
              onChannelsChanged: (ids) =>
                  setState(() => _exemptChannelIds = ids),
            ),
            if (_serverVerdict case final verdict?) ...[
              const SizedBox(height: 12),
              Text(
                verdict,
                key: const ValueKey('automod-verdict'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      if (widget.validate != null && !_isEditing)
        TextButton(
          key: const ValueKey('automod-check'),
          onPressed: _checking ? null : _check,
          child: const Text('Check'),
        ),
      FilledButton(
        key: const ValueKey('automod-save'),
        onPressed: _draft().isValid ? _save : null,
        child: Text(_isEditing ? 'Save' : 'Create'),
      ),
    ],
  );

  AutoModRuleDraft _draft() => AutoModRuleDraft(
    name: _name.text.trim(),
    // A keyword rule watches messages; a profile rule watches names. Discord
    // refuses the other pairing, so the event follows the trigger rather than
    // being a control the moderator can get wrong.
    eventType: _trigger == AutoModTriggerType.userProfile
        ? AutoModEventType.guildMemberJoinOrUpdate
        : AutoModEventType.messageSend,
    triggerType: _trigger,
    metadata: AutoModTriggerMetadata(
      keywordFilter: _trigger.hasKeywords ? _split(_keywords.text) : const [],
      regexPatterns: _trigger.hasKeywords ? _split(_patterns.text) : const [],
      presets: _trigger == AutoModTriggerType.defaultKeywordList
          ? _presets
          : const [],
      allowList:
          _trigger.hasKeywords ||
              _trigger == AutoModTriggerType.defaultKeywordList
          ? _split(_allowList.text)
          : const [],
      mentionTotalLimit: _trigger == AutoModTriggerType.mentionSpam
          ? int.tryParse(_mentionLimit.text.trim()) ?? 0
          : 0,
    ),
    actions: _actions(),
    exemptRoleIds: _exemptRoleIds,
    exemptChannelIds: _exemptChannelIds,
  );

  List<AutoModAction> _actions() => [
    if (_blockMessage)
      const AutoModAction(type: AutoModActionType.blockMessage),
    if (_alertChannelId.isNotEmpty)
      AutoModAction(
        type: AutoModActionType.flagToChannel,
        channelId: _alertChannelId,
      ),
    if (_timeout > Duration.zero)
      AutoModAction(
        type: AutoModActionType.userCommunicationDisabled,
        durationSeconds: _timeout.inSeconds,
      ),
  ];

  Future<void> _check() async {
    setState(() => _checking = true);
    final verdict = await widget.validate!(_draft());
    if (!mounted) return;
    setState(() {
      _checking = false;
      _serverVerdict = verdict ?? 'The server would accept this rule.';
    });
  }

  void _save() {
    if (!_isEditing) {
      Navigator.of(context).pop(AutoModRuleDialogResult.create(_draft()));
      return;
    }
    final rule = widget.rule!;
    final draft = _draft();
    final edit = AutoModRuleEdit();
    if (draft.name != rule.name) edit.name = draft.name;
    if (draft.metadata != rule.metadata) edit.metadata = draft.metadata;
    if (!_sameActions(draft.actions, rule.actions)) {
      edit.actions = draft.actions;
    }
    if (!_sameIds(draft.exemptRoleIds, rule.exemptRoleIds)) {
      edit.exemptRoleIds = draft.exemptRoleIds;
    }
    if (!_sameIds(draft.exemptChannelIds, rule.exemptChannelIds)) {
      edit.exemptChannelIds = draft.exemptChannelIds;
    }
    // An edit that changed nothing is closed rather than sent: the server
    // would accept it and write an audit-log entry saying nothing happened.
    Navigator.of(
      context,
    ).pop(edit.isEmpty ? null : AutoModRuleDialogResult.update(edit));
  }

  static bool _sameActions(List<AutoModAction> a, List<AutoModAction> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

  /// Order-insensitive: the rule states its exemptions in whatever order the
  /// server returned them, and reordering is not a change to send.
  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final left = [...a]..sort();
    final right = [...b]..sort();
    return [
      for (var i = 0; i < left.length; i++) left[i] == right[i],
    ].every((same) => same);
  }

  static List<String> _split(String text) => [
    for (final part in text.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// The name Discord's own page gives each trigger.
String autoModTriggerLabel(AutoModTriggerType trigger) => switch (trigger) {
  AutoModTriggerType.keyword => 'Custom words',
  AutoModTriggerType.spamLink => 'Suspicious links',
  AutoModTriggerType.mlSpam => 'Spam content',
  AutoModTriggerType.defaultKeywordList => "Discord's word lists",
  AutoModTriggerType.mentionSpam => 'Mention spam',
  AutoModTriggerType.userProfile => 'Member profiles',
  AutoModTriggerType.serverPolicy => 'Server policy',
  AutoModTriggerType.unknown => 'Unsupported',
};
