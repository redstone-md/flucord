import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'discord_identity_profile_popover.dart';
import 'member_avatar.dart';

class MemberProfilePopover extends StatelessWidget {
  const MemberProfilePopover({
    required this.member,
    required this.spaceId,
    required this.canMessage,
    required this.onMessage,
    super.key,
  });

  final Member member;
  final String spaceId;
  final bool canMessage;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) => DiscordIdentityProfilePopover(
    key: const ValueKey('member-profile-popover'),
    semanticsLabel: '${member.displayName} profile',
    displayName: member.displayName,
    statusLabel: _presenceLabel(member.presence),
    userId: member.id,
    bannerColor: Color(member.colorValue),
    avatar: MemberAvatar(
      member: member,
      spaceId: spaceId,
      size: 64,
      presenceBorderColor: context.surfaces.raised,
    ),
    details: [
      DiscordIdentityProfileDetail(
        label: 'ROLE',
        value: member.roleFor(spaceId),
        indicatorColor: Color(member.colorValue),
      ),
    ],
    canMessage: canMessage,
    onMessage: onMessage,
    copyButtonKey: const ValueKey('copy-member-id'),
    messageButtonKey: const ValueKey('message-member'),
  );

  static String _presenceLabel(Presence presence) => switch (presence) {
    Presence.online => 'Online',
    Presence.idle => 'Idle',
    Presence.offline => 'Offline',
  };
}
