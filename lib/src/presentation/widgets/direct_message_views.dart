import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/direct_message_candidate.dart';
import '../../theme/flucord_icons.dart';
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
                prefixIcon: FlucordIcon(FlucordIcons.search, size: 16),
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
      actions: const [FlucordDialogCancel()],
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
            child: const FlucordIcon(FlucordIcons.person, size: 16),
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

  static const _iconSize = 32.0;

  final VoidCallback onNewMessage;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlucordIcon(
          FlucordIcons.directMessages,
          size: _iconSize,
          color: context.surfaces.muted,
        ),
        const SizedBox(height: 12),
        Text(
          'No direct messages',
          style: FlucordTextRole.heading.style.copyWith(
            color: context.surfaces.text,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onNewMessage,
          icon: const FlucordIcon(FlucordIcons.edit, size: 16),
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

/// What a DM opens on, above its first message: the person, large, and a
/// line that says this is where the history starts.
class DirectMessageStart extends StatelessWidget {
  const DirectMessageStart({
    required this.avatar,
    required this.name,
    super.key,
  });

  /// The size [avatar] is drawn at.
  static const avatarSize = 80.0;

  final Widget avatar;
  final String name;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: avatarSize, child: avatar),
          const SizedBox(height: 12),
          Text(
            name,
            style: FlucordTextRole.display.style.copyWith(color: surfaces.text),
          ),
          const SizedBox(height: 4),
          Text(
            'This is the beginning of your direct message history with $name.',
            style: FlucordTextRole.body.style.copyWith(color: surfaces.muted),
          ),
        ],
      ),
    );
  }
}
