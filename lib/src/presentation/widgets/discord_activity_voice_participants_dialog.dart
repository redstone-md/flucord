import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/discord_social_activity_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../theme/flucord_theme.dart';
import 'discord_friends_scope.dart';
import 'discord_relationship_avatar.dart';

Future<void> showDiscordActivityVoiceParticipantsDialog(
  BuildContext context,
  DiscordSocialActivityController controller,
) {
  final relationships =
      DiscordFriendsScope.maybeOf(context)?.relationships ?? const [];
  return showDialog<void>(
    context: context,
    builder: (context) => _ParticipantsDialog(
      controller: controller,
      relationships: relationships,
    ),
  );
}

class _ParticipantsDialog extends StatelessWidget {
  const _ParticipantsDialog({
    required this.controller,
    required this.relationships,
  });

  final DiscordSocialActivityController controller;
  final List<DiscordRelationship> relationships;

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final call = controller.call;
          final participants = call?.participantUserIds ?? const <String>[];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                count: participants.length,
                connected: call?.isConnected == true,
              ),
              Divider(height: 1, color: context.surfaces.border),
              if (participants.isEmpty)
                const _EmptyParticipants()
              else
                Flexible(
                  child: ListView.separated(
                    key: const ValueKey('activity-voice-participant-list'),
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: participants.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final userId = participants[index];
                      return _ParticipantRow(
                        user: _userFor(userId),
                        speaking: call?.isSpeaking(userId) == true,
                        currentUser: userId == call?.currentUserId,
                        locallyMuted: call?.isLocallyMuted(userId) == true,
                        pending: controller.isParticipantMutePending(userId),
                        error: controller.participantMuteErrorFor(userId),
                        onToggleMuted: () => unawaited(
                          controller.toggleParticipantMuted(userId),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

  DiscordRelationshipUser _userFor(String userId) {
    for (final relationship in relationships) {
      if (relationship.user.id == userId) return relationship.user;
    }
    return DiscordRelationshipUser(
      id: userId,
      displayName: 'Discord user · $userId',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.connected});

  final int count;
  final bool connected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    child: Row(
      children: [
        Icon(
          Icons.headset_mic_outlined,
          size: 20,
          color: connected ? FlucordColors.success : context.surfaces.muted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Activity voice',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '$count participant${count == 1 ? '' : 's'}',
                style: TextStyle(color: context.surfaces.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('close-activity-voice-participants'),
          tooltip: 'Close participants',
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.user,
    required this.speaking,
    required this.currentUser,
    required this.locallyMuted,
    required this.pending,
    required this.error,
    required this.onToggleMuted,
  });

  final DiscordRelationshipUser user;
  final bool speaking;
  final bool currentUser;
  final bool locallyMuted;
  final bool pending;
  final String? error;
  final VoidCallback onToggleMuted;

  @override
  Widget build(BuildContext context) => Semantics(
    label: [
      currentUser ? 'You' : user.displayName,
      speaking ? 'speaking' : 'connected',
      if (locallyMuted) 'locally muted',
    ].join(', '),
    child: Padding(
      key: ValueKey('activity-voice-participant-${user.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: speaking ? FlucordColors.success : Colors.transparent,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: DiscordRelationshipAvatar(user: user, size: 36),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentUser ? 'You' : user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _connectionLabel,
                  style: TextStyle(
                    color: speaking
                        ? FlucordColors.success
                        : context.surfaces.muted,
                    fontSize: 11,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 2),
                  const Text(
                    'Could not update local volume',
                    key: ValueKey('activity-participant-mute-error'),
                    style: TextStyle(color: FlucordColors.danger, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          if (speaking)
            const Icon(
              Icons.graphic_eq,
              color: FlucordColors.success,
              size: 20,
            ),
          if (!currentUser) ...[
            const SizedBox(width: 4),
            if (pending)
              SizedBox.square(
                key: ValueKey('activity-participant-mute-pending-${user.id}'),
                dimension: 32,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                key: ValueKey('toggle-activity-participant-mute-${user.id}'),
                tooltip: error != null
                    ? 'Retry local volume change'
                    : locallyMuted
                    ? 'Unmute ${user.displayName}'
                    : 'Mute ${user.displayName}',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleMuted,
                icon: Icon(
                  error != null
                      ? Icons.refresh
                      : locallyMuted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  size: 19,
                  color: locallyMuted
                      ? FlucordColors.brand
                      : context.surfaces.muted,
                ),
              ),
          ],
        ],
      ),
    ),
  );

  String get _connectionLabel {
    final status = speaking ? 'Speaking' : 'Connected';
    return locallyMuted ? '$status · Locally muted' : status;
  }
}

class _EmptyParticipants extends StatelessWidget {
  const _EmptyParticipants();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      'Waiting for voice participants…',
      textAlign: TextAlign.center,
      style: TextStyle(color: context.surfaces.muted, fontSize: 12),
    ),
  );
}
