import 'package:flutter/material.dart';

import '../../application/discord_social_activity_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/discord_social_activity.dart';
import '../../domain/discord_social_call.dart';
import '../../theme/flucord_theme.dart';
import 'discord_activity_voice_participants_dialog.dart';
import 'discord_friends_scope.dart';
import 'discord_relationship_avatar.dart';
import 'discord_social_activity_scope.dart';

class DiscordActivityInviteStrip extends StatelessWidget {
  const DiscordActivityInviteStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DiscordSocialActivityScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    if (controller.session case final session?
        when controller.call?.isActive == true || controller.callPending) {
      return _JoinedSession(controller: controller, session: session);
    }
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
  Widget build(BuildContext context) {
    final call = controller.call;
    final active = call?.isActive == true;
    return Container(
      key: const ValueKey('discord-activity-session-joined'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border(bottom: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.headset_mic_outlined, size: 18, color: _statusColor(call)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(call),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _detail(call),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: controller.callError == null
                        ? context.surfaces.muted
                        : FlucordColors.danger,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (controller.callPending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!active)
            FilledButton(
              key: const ValueKey('start-activity-voice'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: controller.startVoice,
              child: const Text('Join voice'),
            )
          else ...[
            Badge(
              label: Text('${call!.participantUserIds.length}'),
              backgroundColor: context.surfaces.control,
              textColor: Theme.of(context).colorScheme.onSurface,
              child: _CallButton(
                key: const ValueKey('show-activity-voice-participants'),
                tooltip: 'Voice participants',
                icon: Icons.group_outlined,
                onPressed: () => showDiscordActivityVoiceParticipantsDialog(
                  context,
                  controller,
                ),
              ),
            ),
            _CallButton(
              key: const ValueKey('toggle-activity-mute'),
              tooltip: call.selfMuted ? 'Unmute' : 'Mute',
              icon: call.selfMuted ? Icons.mic_off : Icons.mic,
              active: call.selfMuted,
              onPressed: controller.toggleMuted,
            ),
            _CallButton(
              key: const ValueKey('toggle-activity-deafen'),
              tooltip: call.selfDeafened ? 'Undeafen' : 'Deafen',
              icon: call.selfDeafened
                  ? Icons.headset_off
                  : Icons.headphones_outlined,
              active: call.selfDeafened,
              onPressed: controller.toggleDeafened,
            ),
            _CallButton(
              key: const ValueKey('leave-activity-voice'),
              tooltip: 'Leave activity voice',
              icon: Icons.call_end,
              color: FlucordColors.danger,
              onPressed: controller.leaveVoice,
            ),
          ],
          if (!active && !controller.callPending)
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

  Color? _statusColor(DiscordSocialCallState? call) => switch (call?.status) {
    DiscordSocialCallStatus.connected => FlucordColors.success,
    DiscordSocialCallStatus.reconnecting => FlucordColors.warning,
    DiscordSocialCallStatus.disconnected => FlucordColors.danger,
    _ => null,
  };

  String _title(DiscordSocialCallState? call) => switch (call?.status) {
    DiscordSocialCallStatus.connected => 'Activity voice connected',
    DiscordSocialCallStatus.reconnecting => 'Activity voice reconnecting',
    DiscordSocialCallStatus.disconnecting => 'Leaving activity voice',
    DiscordSocialCallStatus.joining ||
    DiscordSocialCallStatus.connecting ||
    DiscordSocialCallStatus.signalingConnected => 'Connecting activity voice',
    _ => 'Joined Flucord activity lobby',
  };

  String _detail(DiscordSocialCallState? call) {
    if (controller.callError != null) return 'Voice connection failed · Retry';
    if (call?.isActive != true) return 'Lobby ${session.lobbyId} · Voice idle';
    final count = call!.participantUserIds.length;
    return 'Lobby ${session.lobbyId} · $count voice participant${count == 1 ? '' : 's'}';
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.color,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    color: color ?? (active ? FlucordColors.brand : null),
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
  );
}
