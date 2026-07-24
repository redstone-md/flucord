import 'package:flutter/material.dart';

import '../../application/discord_friends_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../theme/flucord_theme.dart';

class DiscordFriendActions extends StatelessWidget {
  const DiscordFriendActions({
    required this.controller,
    required this.relationship,
    super.key,
  });

  final DiscordFriendsController controller;
  final DiscordRelationship relationship;

  @override
  Widget build(BuildContext context) {
    final userId = relationship.user.id;
    if (controller.isMutating(userId)) {
      return const SizedBox.square(
        key: ValueKey('discord-friend-action-pending'),
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (relationship.kind == DiscordRelationshipKind.incomingRequest) ...[
          _ActionButton(
            key: ValueKey('discord-friend-accept-$userId'),
            tooltip: 'Accept friend request',
            icon: Icons.check,
            color: FlucordColors.success,
            onPressed: () =>
                _perform(context, DiscordRelationshipAction.acceptRequest),
          ),
          _ActionButton(
            key: ValueKey('discord-friend-reject-$userId'),
            tooltip: 'Reject friend request',
            icon: Icons.close,
            onPressed: () =>
                _perform(context, DiscordRelationshipAction.rejectRequest),
          ),
        ] else if (relationship.kind == DiscordRelationshipKind.outgoingRequest)
          _ActionButton(
            key: ValueKey('discord-friend-cancel-$userId'),
            tooltip: 'Cancel friend request',
            icon: Icons.close,
            onPressed: () =>
                _perform(context, DiscordRelationshipAction.cancelRequest),
          ),
        _MoreActions(
          relationship: relationship,
          onSelected: (action) => _perform(context, action),
        ),
      ],
    );
  }

  Future<void> _perform(
    BuildContext context,
    DiscordRelationshipAction action,
  ) async {
    if (_requiresConfirmation(action)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) =>
            _ConfirmationDialog(relationship: relationship, action: action),
      );
      if (confirmed != true || !context.mounted) return;
    }
    await controller.updateRelationship(relationship, action);
  }

  static bool _requiresConfirmation(DiscordRelationshipAction action) =>
      action == DiscordRelationshipAction.removeFriend ||
      action == DiscordRelationshipAction.blockUser;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      onPressed: onPressed,
      icon: Icon(icon, size: 17, color: color ?? context.surfaces.muted),
    );
  }
}

class _MoreActions extends StatelessWidget {
  const _MoreActions({required this.relationship, required this.onSelected});

  final DiscordRelationship relationship;
  final ValueChanged<DiscordRelationshipAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final actions = <DiscordRelationshipAction>[
      if (relationship.kind == DiscordRelationshipKind.friend)
        DiscordRelationshipAction.removeFriend,
      DiscordRelationshipAction.blockUser,
    ].where(relationship.supports).toList(growable: false);
    if (actions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<DiscordRelationshipAction>(
      key: ValueKey('discord-friend-more-${relationship.user.id}'),
      tooltip: 'More relationship actions',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem(
            value: action,
            child: Text(
              _menuLabel(action),
              style: action == DiscordRelationshipAction.blockUser
                  ? const TextStyle(color: FlucordColors.danger)
                  : null,
            ),
          ),
      ],
      icon: Icon(Icons.more_horiz, size: 18, color: context.surfaces.muted),
    );
  }

  static String _menuLabel(DiscordRelationshipAction action) =>
      switch (action) {
        DiscordRelationshipAction.removeFriend => 'Remove Friend',
        DiscordRelationshipAction.blockUser => 'Block',
        _ => action.name,
      };
}

class _ConfirmationDialog extends StatelessWidget {
  const _ConfirmationDialog({required this.relationship, required this.action});

  final DiscordRelationship relationship;
  final DiscordRelationshipAction action;

  @override
  Widget build(BuildContext context) {
    final blocking = action == DiscordRelationshipAction.blockUser;
    final verb = blocking ? 'Block' : 'Remove Friend';
    return AlertDialog(
      title: Text('$verb ${relationship.user.displayName}?'),
      content: Text(
        blocking
            ? 'They will no longer be able to message or invite you through Discord.'
            : 'This removes the Discord and game friendship.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-relationship-action'),
          style: FilledButton.styleFrom(backgroundColor: FlucordColors.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(verb),
        ),
      ],
    );
  }
}
