import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/guild_management.dart';

/// Picks who to ban, for how much history, and why.
///
/// [candidates] is already filtered to members this account outranks, so the
/// dialog never has to explain why somebody is missing — Discord does the same
/// by simply not offering the menu item on a member you cannot ban.
class GuildBanDialog extends StatefulWidget {
  const GuildBanDialog({
    required this.candidates,
    required this.spaceId,
    super.key,
  });

  final List<Member> candidates;
  final String spaceId;

  @override
  State<GuildBanDialog> createState() => _GuildBanDialogState();
}

class _GuildBanDialogState extends State<GuildBanDialog> {
  final Set<String> _selected = {};
  final TextEditingController _reason = TextEditingController();
  BanMessageDeletion _deletion = BanMessageDeletion.standardDefault;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('guild-ban-dialog'),
    title: Text(
      _selected.length > 1 ? 'Ban ${_selected.length} members' : 'Ban member',
    ),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('There is nobody here you can ban.'),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final member in widget.candidates)
                      CheckboxListTile(
                        key: ValueKey('ban-candidate-${member.id}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          member.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: _selected.contains(member.id),
                        onChanged: (checked) => setState(() {
                          if (checked ?? false) {
                            _selected.add(member.id);
                          } else {
                            _selected.remove(member.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<BanMessageDeletion>(
            key: const ValueKey('ban-deletion-window'),
            initialValue: _deletion,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Delete recent messages',
            ),
            items: [
              for (final option in BanMessageDeletion.values)
                DropdownMenuItem(
                  value: option,
                  child: Text(_deletionLabel(option)),
                ),
            ],
            onChanged: (value) =>
                setState(() => _deletion = value ?? _deletion),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('ban-reason'),
            controller: _reason,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Reason (shown in the audit log)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('ban-confirm'),
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.of(context).pop(
                BanRequest(
                  userIds: _selected.toList(growable: false),
                  deletion: _deletion,
                  reason: _reason.text.trim().isEmpty
                      ? null
                      : _reason.text.trim(),
                ),
              ),
        child: const Text('Ban'),
      ),
    ],
  );

  static String _deletionLabel(BanMessageDeletion deletion) =>
      switch (deletion) {
        BanMessageDeletion.none => "Don't delete any",
        BanMessageDeletion.lastHour => 'Previous hour',
        BanMessageDeletion.lastSixHours => 'Previous 6 hours',
        BanMessageDeletion.lastTwelveHours => 'Previous 12 hours',
        BanMessageDeletion.lastDay => 'Previous 24 hours',
        BanMessageDeletion.lastThreeDays => 'Previous 3 days',
        BanMessageDeletion.lastWeek => 'Previous 7 days',
      };
}
