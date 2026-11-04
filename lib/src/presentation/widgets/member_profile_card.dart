import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/active_friends.dart';
import '../../application/guild_member_admin_controller.dart';
import '../../application/member_profile_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import 'flucord_dialog.dart';
import 'member_moderation_section.dart';
import 'profile_card.dart';
import 'profile_card_data.dart';
import 'profile_card_route.dart';
import 'profile_note_section.dart';

/// How a member's profile is drawn: the popout card, or the full profile
/// window it opens.
enum ProfileLayout { card, window }

/// The profile card, or the full profile window, for a workspace member.
///
/// Draws what the workspace knows at once, then lays the fetched profile
/// over it when it arrives: banner, accent, pronouns, bio, badges, the
/// mutuals and the connections. Opening it starts that fetch. A fetch that
/// fails or is refused leaves the parts it would have filled hidden.
class MemberProfileCard extends StatefulWidget {
  const MemberProfileCard({
    required this.member,
    this.layout = ProfileLayout.card,
    this.spaceId,
    this.workspace,
    this.friendsSince,
    this.voiceRoom,
    this.profile,
    this.moderationBuilder,
    this.onMessage,
    this.onAddFriend,
    this.onReport,
    this.onBlock,
    this.onOpenFullProfile,
    this.onOpenProfile,
    this.onOpenServer,
    this.onJoinVoice,
    this.onOpenLink,
    this.now,
    super.key,
  });

  final Member member;
  final ProfileLayout layout;

  /// The server the card was opened in, or null outside one.
  final String? spaceId;

  /// What the member's role ids, mutual servers and mutual friends are read
  /// against.
  final ChatWorkspace? workspace;

  /// When the account and the member became friends, or null.
  final DateTime? friendsSince;

  /// The voice channel the member sits in, or null.
  final ActiveFriendRoom? voiceRoom;

  /// Fetches the full profile and keeps the note. Null on a host with no
  /// account behind it.
  final MemberProfileController? profile;

  /// Builds the moderation controller for this card, or answers null where
  /// the account holds no authority here. The card owns what it builds.
  final GuildMemberAdminController? Function()? moderationBuilder;

  /// Opens the DM with the typed text. Null for the account itself.
  final ValueChanged<String>? onMessage;

  /// Sends a friend request. Null when that makes no sense: a friend, a
  /// request already sent, or the account itself.
  final VoidCallback? onAddFriend;

  /// Opens the report flow. Null where the transport cannot report.
  final VoidCallback? onReport;

  /// Blocks the member. Null for the same reason as [onReport].
  final VoidCallback? onBlock;

  /// See [ProfileCardActions] for these.
  final VoidCallback? onOpenFullProfile;
  final OpenProfileCard? onOpenProfile;
  final ValueChanged<String>? onOpenServer;
  final ValueChanged<String>? onJoinVoice;
  final ValueChanged<Uri>? onOpenLink;
  final DateTime? now;

  @override
  State<MemberProfileCard> createState() => _MemberProfileCardState();
}

class _MemberProfileCardState extends State<MemberProfileCard> {
  GuildMemberAdminController? _moderation;

  @override
  void initState() {
    super.initState();
    unawaited(widget.profile?.open(widget.member.id, serverId: widget.spaceId));
    final moderation = widget.moderationBuilder?.call();
    _moderation = moderation;
    if (moderation != null) unawaited(moderation.load());
  }

  @override
  void dispose() {
    _moderation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.profile, _moderation]),
    builder: (context, _) {
      final roles = _heldRoles();
      final data = ProfileCardData.member(
        widget.member,
        spaceId: widget.spaceId,
        profile: widget.profile?.profile,
        roles: roles,
        workspace: widget.workspace,
        friendsSince: widget.friendsSince,
        voiceRoom: widget.voiceRoom,
      );
      final actions = _actions(
        context,
        held: {...?roles?.map((role) => role.id)},
      );
      return switch (widget.layout) {
        ProfileLayout.card => ProfileCard(
          data: data,
          actions: actions,
          now: widget.now,
        ),
        ProfileLayout.window => FullProfile(
          data: data,
          actions: actions,
          note: switch (widget.profile) {
            final profile? when profile.isSupported => ProfileNoteSection(
              controller: profile,
            ),
            _ => null,
          },
          now: widget.now,
        ),
      };
    },
  );

  /// The roles the member holds here, highest first. The moderation
  /// controller's answer wins once loaded: it follows a role just given.
  List<CommunityRole>? _heldRoles() {
    final spaceId = widget.spaceId;
    if (spaceId == null) return null;
    final rolesById = {
      for (final role in widget.workspace?.roles ?? const <CommunityRole>[])
        if (role.spaceId == spaceId) role.id: role,
    };
    return HeldRoles.ofIds(
      _moderation?.profile?.roleIds ??
          widget.member.membershipIn(spaceId)?.roleIds ??
          const <String>[],
      (roleId) => rolesById[roleId],
    ).highestFirst;
  }

  ProfileCardActions _actions(
    BuildContext context, {
    required Set<String> held,
  }) {
    final moderation = _moderation;
    final assignable = {
      if (moderation != null)
        for (final role in moderation.roles)
          if (moderation.canAssignRole(role)) role.id: role,
    };
    return ProfileCardActions(
      onMessage: widget.onMessage,
      onAddFriend: widget.onAddFriend,
      onAddRole: moderation == null || assignable.isEmpty
          ? null
          : (role) => unawaited(moderation.grantRole(assignable[role.id]!)),
      addableRoles: [
        for (final role in assignable.values)
          if (!held.contains(role.id)) role.asCommunityRole,
      ],
      onOpenFullProfile: widget.onOpenFullProfile,
      onOpenProfile: widget.onOpenProfile,
      onOpenServer: widget.onOpenServer,
      onJoinVoice: widget.onJoinVoice,
      onOpenLink: widget.onOpenLink,
      menu: [
        ProfileCardMenuEntry.copyUserId(
          widget.member.id,
          key: const ValueKey('copy-member-id'),
        ),
        // The window shows the note in place.
        if (widget.profile case final profile?
            when profile.isSupported && widget.layout == ProfileLayout.card)
          ProfileCardMenuEntry(
            key: const ValueKey('profile-card-note'),
            label: 'Note',
            icon: FlucordIcons.edit,
            onSelected: () => unawaited(
              _openDialog(
                context,
                title: 'Note',
                content: ProfileNoteSection(controller: profile),
              ),
            ),
          ),
        if (moderation != null && moderation.hasAnyAction)
          ProfileCardMenuEntry(
            key: const ValueKey('profile-card-moderate'),
            label: 'Moderate',
            icon: FlucordIcons.standing,
            onSelected: () => unawaited(
              _openDialog(
                context,
                title: 'Moderate ${widget.member.displayName}',
                content: MemberModerationSection(controller: moderation),
              ),
            ),
          ),
        if (widget.onReport case final report?)
          ProfileCardMenuEntry(
            key: const ValueKey('report-member'),
            label: 'Report',
            icon: FlucordIcons.report,
            danger: true,
            onSelected: report,
          ),
        if (widget.onBlock case final block?)
          ProfileCardMenuEntry(
            key: const ValueKey('block-member'),
            label: 'Block',
            icon: FlucordIcons.block,
            danger: true,
            onSelected: block,
          ),
      ],
    );
  }

  Future<void> _openDialog(
    BuildContext context, {
    required String title,
    required Widget content,
  }) => showDialog<void>(
    context: context,
    builder: (_) => FlucordDialog(
      title: Text(title),
      content: SingleChildScrollView(child: content),
      actions: const [FlucordDialogCancel(label: 'Close')],
    ),
  );
}
