import 'package:flutter/material.dart';

import '../../domain/discord_relationship.dart';
import '../../theme/flucord_theme.dart';
import 'discord_identity_profile_popover.dart';
import 'discord_relationship_avatar.dart';

class DiscordFriendProfilePopover extends StatelessWidget {
  const DiscordFriendProfilePopover({
    required this.relationship,
    required this.onMessage,
    super.key,
  });

  final DiscordRelationship relationship;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final user = relationship.user;
    final activity = user.activity;
    return DiscordIdentityProfilePopover(
      key: const ValueKey('discord-friend-profile-popover'),
      semanticsLabel: '${user.displayName} Discord profile',
      displayName: user.displayName,
      secondaryLabel: user.username == null ? null : '@${user.username}',
      statusLabel: _presenceLabel(user.status),
      userId: user.id,
      bannerColor: context.surfaces.brand,
      avatar: DiscordRelationshipAvatar(
        user: user,
        size: 64,
        presenceBorderColor: context.surfaces.raised,
      ),
      details: [
        DiscordIdentityProfileDetail(
          label: 'RELATIONSHIP',
          value: _relationshipLabel(relationship.kind),
          indicatorColor: _relationshipColor(context, relationship.kind),
        ),
        if (user.isProvisional)
          const DiscordIdentityProfileDetail(
            label: 'ACCOUNT',
            value: 'Provisional Discord account',
          ),
        if (activity != null)
          DiscordIdentityProfileDetail(
            label: 'PLAYING',
            value: [activity.name, ...activity.description].join('\n'),
            maxLines: 3,
          ),
      ],
      canMessage: relationship.kind == DiscordRelationshipKind.friend,
      onMessage: onMessage,
      copyButtonKey: const ValueKey('copy-friend-id'),
      messageButtonKey: const ValueKey('message-friend-profile'),
    );
  }

  static String _presenceLabel(DiscordPresenceStatus status) =>
      switch (status) {
        DiscordPresenceStatus.online => 'Online',
        DiscordPresenceStatus.idle => 'Idle',
        DiscordPresenceStatus.doNotDisturb => 'Do Not Disturb',
        DiscordPresenceStatus.offline => 'Offline',
        DiscordPresenceStatus.unknown => 'Status unavailable',
      };

  static String _relationshipLabel(DiscordRelationshipKind kind) =>
      switch (kind) {
        DiscordRelationshipKind.friend => 'Friend',
        DiscordRelationshipKind.incomingRequest => 'Incoming friend request',
        DiscordRelationshipKind.outgoingRequest => 'Outgoing friend request',
        DiscordRelationshipKind.blocked => 'Blocked',
        DiscordRelationshipKind.implicit => 'Game relationship',
        DiscordRelationshipKind.unknown => 'Relationship unavailable',
      };

  static Color? _relationshipColor(
    BuildContext context,
    DiscordRelationshipKind kind,
  ) => switch (kind) {
    DiscordRelationshipKind.friend => context.surfaces.success,
    DiscordRelationshipKind.incomingRequest ||
    DiscordRelationshipKind.outgoingRequest => context.surfaces.warning,
    DiscordRelationshipKind.blocked => context.surfaces.danger,
    DiscordRelationshipKind.implicit || DiscordRelationshipKind.unknown => null,
  };
}
