import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/direct_message_candidate.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_dialog.dart';
import 'member_avatar.dart';
import 'remote_identity_image.dart';

/// Finds somebody to message. Pops with their user id.
class DirectMessageDialog extends StatefulWidget {
  const DirectMessageDialog({required this.people, super.key});

  /// Everybody on offer, in the order to list them.
  final List<DirectMessageCandidate> people;

  @override
  State<DirectMessageDialog> createState() => _DirectMessageDialogState();
}

class _DirectMessageDialogState extends State<DirectMessageDialog> {
  String _query = '';

  List<DirectMessageCandidate> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.people;
    return [
      for (final person in widget.people)
        if (person.matches(query)) person,
    ];
  }

  void _open(DirectMessageCandidate person) =>
      Navigator.pop(context, person.id);

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return FlucordDialog(
      title: const Text('New message'),
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('direct-message-search'),
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Search friends and members',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (matches.isNotEmpty) _open(matches.first);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        'Nobody found',
                        style: TextStyle(color: context.surfaces.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (_, index) => _PersonRow(
                        person: matches[index],
                        onPressed: () => _open(matches[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onPressed});

  final DirectMessageCandidate person;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('direct-message-person-${person.id}'),
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: SizedBox.square(
      dimension: 30,
      child: ClipOval(
        child: RemoteIdentityImage(
          url: person.avatarUrl,
          fallback: ColoredBox(
            color: context.surfaces.raised,
            child: const Icon(Icons.person_outline, size: 16),
          ),
        ),
      ),
    ),
    title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: person.isFriend ? const Text('Friend') : null,
    onTap: onPressed,
  );
}

class DirectMessagesEmptyView extends StatelessWidget {
  const DirectMessagesEmptyView({required this.onNewMessage, super.key});

  final VoidCallback onNewMessage;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.forum_outlined,
          size: 34,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        const Text(
          'No direct messages',
          style: TextStyle(
            fontSize: FlucordType.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onNewMessage,
          icon: const Icon(Icons.edit_square, size: 16),
          label: const Text('New message'),
        ),
      ],
    ),
  );
}

/// The person a DM is with, as the chat header draws them before the name:
/// a small avatar with their status dot.
class DirectMessageHeaderAvatar extends StatelessWidget {
  const DirectMessageHeaderAvatar({required this.person, super.key});

  static const size = 24.0;

  final Member person;

  @override
  Widget build(BuildContext context) => MemberAvatar(
    member: person,
    size: size,
    // The dot is cut out of the header it sits on.
    presenceBorderColor: context.surfaces.canvas,
  );
}
