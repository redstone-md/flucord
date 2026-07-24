import 'package:flutter/material.dart';

import '../../application/discord_social_activity_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/discord_social_activity.dart';
import '../../theme/flucord_theme.dart';
import 'discord_friends_scope.dart';
import 'discord_relationship_avatar.dart';
import 'discord_social_activity_scope.dart';

class DiscordActivityInviteStrip extends StatelessWidget {
  const DiscordActivityInviteStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DiscordSocialActivityScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    if (controller.invites case [final invite, ...]) {
      return _IncomingInvite(
        controller: controller,
        invite: invite,
        sender: _sender(context, invite.senderId),
        remainingCount: controller.invites.length - 1,
      );
    }
    if (controller.session case final session?) {
      return _JoinedSession(controller: controller, session: session);
    }
    return const SizedBox.shrink();
  }

  static DiscordRelationshipUser _sender(BuildContext context, String id) {
    final relationships = DiscordFriendsScope.maybeOf(context)?.relationships;
    final matches = relationships?.where((item) => item.user.id == id);
    return matches != null && matches.isNotEmpty
        ? matches.first.user
        : DiscordRelationshipUser(id: id, displayName: 'Discord user');
  }
}

class _IncomingInvite extends StatelessWidget {
  const _IncomingInvite({
    required this.controller,
    required this.invite,
    required this.sender,
    required this.remainingCount,
  });

  final DiscordSocialActivityController controller;
  final DiscordSocialActivityInvite invite;
  final DiscordRelationshipUser sender;
  final int remainingCount;

  @override
  Widget build(BuildContext context) {
    final accepting = controller.isAccepting(invite.key);
    final failed = controller.errorFor(invite.key) != null;
    return Container(
      key: ValueKey('discord-activity-invite-${invite.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border(bottom: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        children: [
          DiscordRelationshipAvatar(user: sender, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sender.displayName} invited you to a Flucord activity',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  failed
                      ? 'Discord rejected the lobby join · Retry'
                      : remainingCount > 0
                      ? 'Activity lobby · $remainingCount more invitation(s)'
                      : 'Activity lobby · Separate from a direct call',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: failed
                        ? FlucordColors.danger
                        : context.surfaces.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: ValueKey('dismiss-activity-invite-${invite.key}'),
            onPressed: accepting
                ? null
                : () => controller.dismissInvite(invite.key),
            child: const Text('Ignore'),
          ),
          const SizedBox(width: 6),
          FilledButton(
            key: ValueKey('accept-activity-invite-${invite.key}'),
            onPressed: accepting ? null : () => controller.acceptInvite(invite),
            child: accepting
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Join'),
          ),
        ],
      ),
    );
  }
}

class _JoinedSession extends StatelessWidget {
  const _JoinedSession({required this.controller, required this.session});

  final DiscordSocialActivityController controller;
  final DiscordSocialActivitySession session;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('discord-activity-session-joined'),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
    decoration: BoxDecoration(
      color: context.surfaces.inset,
      border: Border(bottom: BorderSide(color: context.surfaces.border)),
    ),
    child: Row(
      children: [
        const Icon(Icons.sports_esports_outlined, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Joined Flucord activity lobby · ${session.lobbyId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          key: const ValueKey('dismiss-activity-session-notice'),
          tooltip: 'Dismiss lobby notice',
          visualDensity: VisualDensity.compact,
          onPressed: controller.clearSessionNotice,
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
}
