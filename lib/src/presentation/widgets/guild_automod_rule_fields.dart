import 'package:flutter/material.dart';

import '../../domain/automod_rule.dart';

/// The word lists Discord keeps, which a guild switches on rather than writes.
///
/// The contents are server-side and never reach a client, so there is nothing
/// to show but the name — which is exactly what Discord's own page shows.
class AutoModPresetField extends StatelessWidget {
  const AutoModPresetField({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<AutoModKeywordPreset> selected;
  final ValueChanged<List<AutoModKeywordPreset>> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        "Discord's word lists",
        style: Theme.of(context).textTheme.labelLarge,
      ),
      for (final preset in AutoModKeywordPreset.values)
        // The unknown member exists so an unrecognised preset survives a
        // round trip; offering it as a checkbox would be offering nothing.
        if (preset != AutoModKeywordPreset.unknown)
          CheckboxListTile(
            key: ValueKey('automod-preset-${preset.name}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: selected.contains(preset),
            title: Text(autoModPresetLabel(preset)),
            onChanged: (checked) => onChanged([
              for (final value in AutoModKeywordPreset.values)
                if (value != AutoModKeywordPreset.unknown &&
                    (checked ?? false
                        ? value == preset || selected.contains(value)
                        : value != preset && selected.contains(value)))
                  value,
            ]),
          ),
    ],
  );
}

/// One thing a rule can be told to skip: a role or a channel.
///
/// Named here rather than taking roles and channels in their own types
/// because the control does the same thing with both, and the settings window
/// and the sidebar spell a role differently.
final class AutoModExemptTarget {
  const AutoModExemptTarget({required this.id, required this.label});

  final String id;
  final String label;
}

/// Roles and channels the rule does not apply to.
///
/// Discord replaces these lists wholesale on every write, so the control
/// hands back the finished list rather than an add or a remove.
class AutoModExemptionField extends StatelessWidget {
  const AutoModExemptionField({
    required this.roles,
    required this.channels,
    required this.exemptRoleIds,
    required this.exemptChannelIds,
    required this.onRolesChanged,
    required this.onChannelsChanged,
    super.key,
  });

  final List<AutoModExemptTarget> roles;
  final List<AutoModExemptTarget> channels;
  final List<String> exemptRoleIds;
  final List<String> exemptChannelIds;
  final ValueChanged<List<String>> onRolesChanged;
  final ValueChanged<List<String>> onChannelsChanged;

  @override
  Widget build(BuildContext context) {
    final labels = Theme.of(context).textTheme.labelLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Roles this does not apply to', style: labels),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (roles.isEmpty)
              const Text('No roles to exempt.')
            else
              for (final role in roles)
                FilterChip(
                  key: ValueKey('automod-exempt-role-${role.id}'),
                  label: Text(role.label),
                  selected: exemptRoleIds.contains(role.id),
                  onSelected: (selected) => onRolesChanged(
                    _toggled(exemptRoleIds, role.id, selected: selected),
                  ),
                ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Channels this does not apply to', style: labels),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (channels.isEmpty)
              const Text('No channels to exempt.')
            else
              for (final channel in channels)
                FilterChip(
                  key: ValueKey('automod-exempt-channel-${channel.id}'),
                  label: Text(channel.label),
                  selected: exemptChannelIds.contains(channel.id),
                  onSelected: (selected) => onChannelsChanged(
                    _toggled(exemptChannelIds, channel.id, selected: selected),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  /// Keeps the order the guild lists things in rather than the order they were
  /// clicked, so an unchanged selection encodes identically twice and an edit
  /// does not report a change nobody made.
  static List<String> _toggled(
    List<String> current,
    String id, {
    required bool selected,
  }) => [
    for (final value in current)
      if (value != id) value,
    if (selected) id,
  ]..sort();
}

/// The name Discord's own page gives each preset list.
String autoModPresetLabel(AutoModKeywordPreset preset) => switch (preset) {
  AutoModKeywordPreset.profanity => 'Profanity',
  AutoModKeywordPreset.sexualContent => 'Sexual content',
  AutoModKeywordPreset.slurs => 'Slurs',
  AutoModKeywordPreset.unknown => 'Unsupported',
};
