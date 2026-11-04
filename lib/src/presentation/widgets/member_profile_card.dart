import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/guild_member_admin_controller.dart';
import '../../application/member_profile_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import 'flucord_dialog.dart';
import 'member_moderation_section.dart';
import 'profile_card.dart';
import 'profile_card_data.dart';
import 'profile_note_section.dart';

/// The profile card for a workspace member.
///
/// Draws what the workspace knows at once, then lays the fetched profile
/// over it when it arrives: banner, accent, pronouns, bio, badges and the
/// mutual counts. Opening the card starts that fetch. A fetch that fails or
/// is refused leaves the parts it would have filled hidden.
class MemberProfileCard extends StatefulWidget {
  const MemberProfileCard({
    required this.member,
    this.spaceId,
    this.roles = const [],
    this.profile,
    this.moderationBuilder,
    this.onMessage,
    this.onAddFriend,
    this.onReport,
    this.onBlock,
    this.now,
    super.key,
  });

  final Member member;

  /// The server the card was opened in, or null outside one.
  final String? spaceId;

  /// The workspace's roles, which the member's role ids are read against.
  final List<CommunityRole> roles;

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
  final DateTime? now;

  @override
  State<MemberProfileCard> createState() => _MemberProfileCardState();
}

class _MemberProfileCardState extends State<MemberProfileCard> {
  GuildMemberAdminController? _moderation;

  @override
  void initState() {
    super.initState();
    unawaited(widget.profile?.open(widget.member.id));
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
      return ProfileCard(
        data: ProfileCardData.member(
          widget.member,
          spaceId: widget.spaceId,
          profile: widget.profile?.profile,
          roles: roles,
        ),
        actions: _actions(context, held: {...?roles?.map((role) => role.id)}),
        now: widget.now,
      );
    },
  );

  /// The roles the member holds here, highest first. The moderation
  /// controller's answer wins once loaded: it follows a role just given.
  List<CommunityRole>? _heldRoles() {
    final spaceId = widget.spaceId;
    if (spaceId == null) return null;
    final rolesById = {
      for (final role in widget.roles)
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
      menu: [
        ProfileCardMenuEntry(
          key: const ValueKey('copy-member-id'),
          label: 'Copy user ID',
          icon: FlucordIcons.id,
          onSelected: () => unawaited(
            Clipboard.setData(ClipboardData(text: widget.member.id)),
          ),
        ),
        if (widget.profile case final profile? when profile.isSupported)
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
