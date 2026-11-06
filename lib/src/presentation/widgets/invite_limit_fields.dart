import 'package:flutter/material.dart';

import '../../domain/guild_management.dart';

/// The expiry and use-cap choices of an invite, as Discord's invite dialog
/// offers them. Shared by the server settings page and Invite people.
///
/// The fields are keyed `<keyPrefix>-expiry` and `<keyPrefix>-uses`.
class InviteLimitFields extends StatelessWidget {
  const InviteLimitFields({
    required this.keyPrefix,
    required this.maxAgeSeconds,
    required this.maxUses,
    required this.onMaxAgeChanged,
    required this.onMaxUsesChanged,
    super.key,
  });

  final String keyPrefix;
  final int maxAgeSeconds;
  final int maxUses;

  /// Null disables the field, such as while a link is being made.
  final ValueChanged<int>? onMaxAgeChanged;
  final ValueChanged<int>? onMaxUsesChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _choice(
        key: '$keyPrefix-expiry',
        label: 'Expires after',
        value: maxAgeSeconds,
        choices: InviteOptions.maxAgeChoices,
        describe: _expiryLabel,
        onChanged: onMaxAgeChanged,
      ),
      const SizedBox(height: 10),
      _choice(
        key: '$keyPrefix-uses',
        label: 'Maximum uses',
        value: maxUses,
        choices: InviteOptions.maxUsesChoices,
        describe: (uses) => uses == 0 ? 'No limit' : '$uses uses',
        onChanged: onMaxUsesChanged,
      ),
    ],
  );

  static Widget _choice({
    required String key,
    required String label,
    required int value,
    required List<int> choices,
    required String Function(int) describe,
    required ValueChanged<int>? onChanged,
  }) => DropdownButtonFormField<int>(
    key: ValueKey(key),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(isDense: true, labelText: label),
    items: [
      for (final choice in choices)
        DropdownMenuItem(value: choice, child: Text(describe(choice))),
    ],
    onChanged: onChanged == null
        ? null
        : (choice) {
            if (choice != null) onChanged(choice);
          },
  );

  /// How long an invite lasts, in Discord's words. Zero is "Never".
  static String _expiryLabel(int seconds) => switch (seconds) {
    0 => 'Never',
    1800 => '30 minutes',
    3600 => '1 hour',
    21600 => '6 hours',
    43200 => '12 hours',
    86400 => '1 day',
    _ => '7 days',
  };
}
