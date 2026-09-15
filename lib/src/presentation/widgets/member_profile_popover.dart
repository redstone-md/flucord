import 'package:flutter/material.dart';

import '../../application/guild_member_admin_controller.dart';
import '../../application/member_profile_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_theme.dart';
import 'activity_views.dart';
import 'discord_identity_profile_popover.dart';
import 'full_profile_sections.dart';
import 'member_avatar.dart';
import 'member_moderation_section.dart';
import 'remote_identity_image.dart';

/// The member popover: the identity block the roster knows about, plus the
/// full profile fetched from Discord.
///
/// The member row already carries the name, role and presence, so the popover
/// draws those at once and then fetches the rest: bio, banner, badges,
/// decoration, connections, mutuals, and this account's private note. A
/// fetch that fails or comes back refused draws the identity block on its own
/// rather than an error where a person's name should be.
class MemberProfilePopover extends StatelessWidget {
  const MemberProfilePopover({
    required this.member,
    required this.spaceId,
    required this.canMessage,
    required this.onMessage,
    this.profile,
    this.onReport,
    this.onBlock,
    this.moderation,
    this.now,
    super.key,
  });

  final Member member;
  final String spaceId;
  final bool canMessage;
  final VoidCallback onMessage;

  /// Drives the full-profile fetch and the note. Null on a host with no
  /// account behind it, which draws the identity block and nothing else.
  final MemberProfileController? profile;

  /// Opens the in-app report flow for this member. Absent on a transport that
  /// cannot reach `/reporting`.
  final VoidCallback? onReport;

  /// Blocks this member. Absent for the same kind of reason: only a session
  /// that owns the account's relationships can change one.
  final VoidCallback? onBlock;

  /// The moderation block, when the host built one for this member. Absent
  /// where the account holds no authority over them, or the transport has no
  /// guild-administration plane at all.
  final GuildMemberAdminController? moderation;

  /// The moment elapsed times are measured against. Injected so a test can pin
  /// it; the popover is transient, so it is read once when it opens.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    // The profile arrives after the popover is on screen, so the whole card
    // listens for it. A controller that is null needs no listener.
    final profile = this.profile;
    return ListenableBuilder(
      listenable: profile ?? _NoListen(),
      builder: (context, _) => _build(context, profile),
    );
  }

  Widget _build(BuildContext context, MemberProfileController? profile) {
    final presence = member.presenceOrCoarse;
    final custom = presence.customStatus;
    final rich = presence.richActivity;
    final fetched = profile?.profile;
    return DiscordIdentityProfilePopover(
      key: const ValueKey('member-profile-popover'),
      semanticsLabel: '${member.displayName} profile',
      displayName: member.displayName,
      statusLabel: PresenceIndicatorLabel.of(presence),
      secondaryLabel: custom?.summary.isNotEmpty ?? false
          ? custom!.summary
          : null,
      userId: member.id,
      bannerColor: Color(fetched?.accentColor ?? member.colorValue),
      bannerImage: _bannerImage(fetched),
      avatar: _avatar(fetched, context),
      badges: fetched == null || fetched.badges.isEmpty
          ? null
          : ProfileBadgeRow(badges: fetched.badges, compact: true),
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
      body: profile == null ? null : FullProfileSections(controller: profile),
      canMessage: canMessage,
      onMessage: onMessage,
      copyButtonKey: const ValueKey('copy-member-id'),
      messageButtonKey: const ValueKey('message-member'),
      moderation: moderation == null
          ? null
          : MemberModerationSection(controller: moderation!),
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

  /// The avatar with its decoration laid over it, the way Discord draws one:
  /// the decoration asset is larger than the avatar and centred on it.
  Widget _avatar(OtherUserProfile? profile, BuildContext context) {
    final avatar = MemberAvatar(
      member: member,
      spaceId: spaceId,
      size: 64,
      presenceBorderColor: context.surfaces.raised,
    );
    final asset = profile?.decoration?.asset;
    if (asset == null || asset.isEmpty) return avatar;
    return SizedBox.square(
      dimension: 64,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: avatar),
          SizedBox.square(
            dimension: 96,
            child: RemoteIdentityImage(
              key: const ValueKey('member-profile-decoration'),
              url:
                  'https://cdn.discordapp.com/avatar-decoration-decoration/$asset.png?size=96&passthrough=true',
              fallback: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// The banner image the profile carries, or null when there is none.
  ///
  /// The hash is the CDN's own; an account with no banner keeps the accent
  /// colour, which is what the fallback colour slot draws.
  static Widget? _bannerImage(OtherUserProfile? profile) {
    final bannerHash = profile?.bannerHash;
    if (bannerHash == null || bannerHash.isEmpty) return null;
    final format = bannerHash.startsWith('a_') ? 'gif' : 'webp';
    return RemoteIdentityImage(
      key: const ValueKey('member-profile-banner'),
      url:
          'https://cdn.discordapp.com/banners/${profile!.userId}/$bannerHash.$format?size=600',
      fallback: const SizedBox.shrink(),
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

/// A listenable that never fires, for a popover with no profile controller.
final class _NoListen with ChangeNotifier {
  _NoListen();
}

/// The status sentence a profile shows under a name.
///
/// Separate from the dot's own semantics label so that a caller which is not
/// drawing a dot — the profile header, a tooltip — still says the same words.
abstract final class PresenceIndicatorLabel {
  static String of(UserPresence presence) => presence.status.label;
}
