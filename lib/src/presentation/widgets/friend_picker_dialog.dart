import 'package:flutter/material.dart';

import '../../domain/direct_message_candidate.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import 'direct_message_views.dart';
import 'flucord_dialog.dart';

/// Picks several friends, to start a group DM or to add them to one. Pops
/// with their ids, in the order they were picked.
class FriendPickerDialog extends StatefulWidget {
  const FriendPickerDialog({
    required this.title,
    required this.confirmLabel,
    required this.friends,
    required this.maxPicked,
    this.minPicked = 1,
    super.key,
  });

  final String title;
  final String confirmLabel;

  /// Everybody on offer, in the order to list them.
  final List<DirectMessageCandidate> friends;

  /// How many can be picked at most.
  final int maxPicked;

  /// How many must be picked before the dialog can confirm.
  final int minPicked;

  @override
  State<FriendPickerDialog> createState() => _FriendPickerDialogState();
}

class _FriendPickerDialogState extends State<FriendPickerDialog> {
  final List<String> _picked = [];
  String _query = '';

  List<DirectMessageCandidate> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.friends;
    return [
      for (final friend in widget.friends)
        if (friend.matches(query)) friend,
    ];
  }

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id) && _picked.length < widget.maxPicked) {
      _picked.add(id);
    }
  });

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final left = widget.maxPicked - _picked.length;
    return FlucordDialog(
      title: Text(widget.title),
      description: left == 1
          ? 'You can add 1 more friend.'
          : 'You can add $left more friends.',
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('friend-picker-search'),
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search friends',
                prefixIcon: FlucordIcon(FlucordIcons.search, size: 16),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        'No friends found',
                        style: TextStyle(color: context.surfaces.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (_, index) {
                        final friend = matches[index];
                        final picked = _picked.contains(friend.id);
                        return CheckboxListTile(
                          key: ValueKey('friend-picker-${friend.id}'),
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          value: picked,
                          onChanged: picked || left > 0
                              ? (_) => _toggle(friend.id)
                              : null,
                          secondary: CandidateAvatar(url: friend.avatarUrl),
                          title: Text(
                            friend.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      confirm: FlucordDialogConfirm(
        key: const ValueKey('friend-picker-confirm'),
        label: widget.confirmLabel,
        onPressed: _picked.length >= widget.minPicked
            ? () => Navigator.pop(context, List<String>.of(_picked))
            : null,
      ),
    );
  }
}
