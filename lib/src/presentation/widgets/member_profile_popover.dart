import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'activity_views.dart';
import 'discord_identity_profile_popover.dart';
import 'member_avatar.dart';

class MemberProfilePopover extends StatelessWidget {
  const MemberProfilePopover({
    required this.member,
    required this.spaceId,
    required this.canMessage,
    required this.onMessage,
    this.onReport,
    this.onBlock,
    this.now,
    super.key,
  });

  final Member member;
  final String spaceId;
  final bool canMessage;
  final VoidCallback onMessage;

  /// Opens the in-app report flow for this member. Absent on a transport that
  /// cannot reach `/reporting`.
  final VoidCallback? onReport;

  /// Blocks this member. Absent for the same kind of reason: only a session
  /// that owns the account's relationships can change one.
  final VoidCallback? onBlock;

  /// The moment elapsed times are measured against. Injected so a test can pin
  /// it; the popover is transient, so it is read once when it opens.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final presence = member.presenceOrCoarse;
    final custom = presence.customStatus;
    final rich = presence.richActivity;
    return DiscordIdentityProfilePopover(
      key: const ValueKey('member-profile-popover'),
      semanticsLabel: '${member.displayName} profile',
      displayName: member.displayName,
      statusLabel: PresenceIndicatorLabel.of(presence),
      secondaryLabel: custom?.summary.isNotEmpty ?? false
          ? custom!.summary
          : null,
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
      // Discord puts the rich-presence card between the identity block and the
      // action buttons, where it is the first thing read after the name.
      extra: rich == null
          ? null
          : ActivityCard(activity: rich, now: now ?? DateTime.now()),
      extraLabel: rich == null ? null : _sectionLabel(rich.type),
      canMessage: canMessage,
      onMessage: onMessage,
      copyButtonKey: const ValueKey('copy-member-id'),
      messageButtonKey: const ValueKey('message-member'),
      safetyActions: [
        if (onReport != null)
          OutlinedButton.icon(
            key: const ValueKey('report-member'),
            onPressed: onReport,
            icon: const Icon(Icons.flag_outlined, size: 15),
            label: const Text('Report'),
          ),
        if (onBlock != null)
          OutlinedButton.icon(
            key: const ValueKey('block-member'),
            onPressed: onBlock,
            icon: const Icon(Icons.block, size: 15),
            label: const Text('Block'),
          ),
      ],
    );
  }

  static String _sectionLabel(ActivityType type) => switch (type) {
    ActivityType.playing => 'PLAYING A GAME',
    ActivityType.streaming => 'LIVE ON STREAM',
    ActivityType.listening => 'LISTENING TO',
    ActivityType.watching => 'WATCHING',
    ActivityType.competing => 'COMPETING IN',
    _ => 'ACTIVITY',
  };
}

/// The status sentence a profile shows under a name.
///
/// Separate from the dot's own semantics label so that a caller which is not
/// drawing a dot — the profile header, a tooltip — still says the same words.
abstract final class PresenceIndicatorLabel {
  static String of(UserPresence presence) {
    final status = presence.displayStatus.label;
    return presence.isMobileOnly ? '$status (mobile)' : status;
  }
}
