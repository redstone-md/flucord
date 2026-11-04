import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/discord_social_dm_controller.dart';
import '../../application/discord_social_sdk_controller.dart';
import '../../domain/discord_oauth.dart';
import '../../domain/discord_relationship.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'discord_add_friend_dialog.dart';
import 'discord_activity_invite_strip.dart';
import 'discord_friend_directory.dart';
import 'discord_friends_scope.dart';
import 'discord_relationship_avatar.dart';
import 'discord_social_dm_navigation_scope.dart';
import 'discord_social_dm_scope.dart';
import 'discord_social_dm_view.dart';
import 'discord_social_sdk_status.dart';
import 'discord_social_sdk_scope.dart';
import 'oauth_account_footer.dart';
import 'oauth_connected_account_directory.dart';
import 'remote_identity_image.dart';
import 'sidebar_row_metrics.dart';

class OAuthAccountSidebar extends StatelessWidget {
  const OAuthAccountSidebar({required this.account, super.key});

  final DiscordOAuthAccount account;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final socialSdk = DiscordSocialSdkScope.of(context);
    final dmController = DiscordSocialDmScope.of(context);
    final navigation = DiscordSocialDmNavigationScope.of(context);
    final caption = FlucordTextRole.caption.style.copyWith(
      color: surfaces.captionText,
    );
    return Container(
      key: const ValueKey('oauth-account-sidebar'),
      width: 236,
      decoration: BoxDecoration(
        color: surfaces.surface,
        border: Border(right: BorderSide(color: surfaces.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: SidebarRowMetrics.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: surfaces.border)),
            ),
            child: Text(
              'Direct messages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlucordTextRole.heading.style.copyWith(
                color: surfaces.text,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(SidebarRowMetrics.listInset),
              children: [
                _SidebarRow(
                  leading: FlucordIcon(
                    FlucordIcons.friends,
                    size: SidebarRowMetrics.iconSize,
                    color: navigation.friendsSelected
                        ? surfaces.text
                        : surfaces.muted,
                  ),
                  label: 'Friends',
                  detail:
                      socialSdk.state == DiscordSocialSdkControllerState.ready
                      ? 'Native social'
                      : 'Unavailable through OAuth',
                  selected: navigation.friendsSelected,
                  onTap: navigation.showFriends,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SidebarRowMetrics.rowPadding,
                    16,
                    SidebarRowMetrics.rowPadding,
                    4,
                  ),
                  child: Text('Direct messages', style: caption),
                ),
                if (dmController.state == DiscordSocialDmLoadState.loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox.square(
                        dimension: SidebarRowMetrics.iconSize,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (dmController.state == DiscordSocialDmLoadState.ready &&
                    dmController.conversations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SidebarRowMetrics.rowPadding,
                    ),
                    child: Text('No recent conversations', style: caption),
                  )
                else
                  for (final conversation in dmController.conversations)
                    _SidebarRow(
                      rowKey: ValueKey(
                        'social-dm-conversation-${conversation.user.id}',
                      ),
                      leading: DiscordRelationshipAvatar(
                        user: conversation.user,
                        size: SidebarRowMetrics.personAvatarSize,
                        presenceBorderColor: surfaces.surface,
                      ),
                      label: conversation.user.displayName,
                      detail: _presenceLabel(conversation.user.status),
                      selected:
                          navigation.selectedUserId == conversation.user.id,
                      onTap: () {
                        navigation.openConversation(conversation.user.id);
                        unawaited(
                          dmController.loadMessages(conversation.user.id),
                        );
                      },
                    ),
              ],
            ),
          ),
          OAuthAccountFooter(account: account),
        ],
      ),
    );
  }
}

class OAuthAccountHomeView extends StatelessWidget {
  const OAuthAccountHomeView({required this.account, super.key});

  final DiscordOAuthAccount account;

  @override
  Widget build(BuildContext context) {
    final socialSdk = DiscordSocialSdkScope.of(context);
    final friendsController = DiscordFriendsScope.maybeOf(context);
    final dmController = DiscordSocialDmScope.of(context);
    final navigation = DiscordSocialDmNavigationScope.of(context);
    final socialAvailable = socialSdk.availability?.isReady ?? false;
    final socialReady = socialSdk.isAuthenticated;
    final selectedUserId = navigation.selectedUserId;
    if (selectedUserId case final userId?) {
      final conversation = dmController.conversationFor(userId);
      if (conversation != null) {
        return DiscordSocialDmView(
          controller: dmController,
          user: conversation.user,
        );
      }
    }
    return Column(
      key: const ValueKey('oauth-account-home-view'),
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.surfaces.border)),
          ),
          child: Row(
            children: [
              const FlucordIcon(FlucordIcons.friends, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Friends', style: FlucordTextRole.label.strong),
              ),
              if (socialAvailable && friendsController != null) ...[
                TextButton(
                  key: const ValueKey('discord-add-friend'),
                  onPressed: friendsController.canSendFriendRequest
                      ? () => showDiscordAddFriendDialog(
                          context,
                          friendsController,
                        )
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: context.surfaces.success,
                    textStyle: FlucordTextRole.caption.strong,
                  ),
                  child: const Text('Add Friend'),
                ),
                const SizedBox(width: 10),
              ],
              FlucordIcon(
                socialReady ? FlucordIcons.friends : FlucordIcons.lock,
                size: 16,
                color: socialReady
                    ? context.surfaces.success
                    : context.surfaces.muted,
              ),
              const SizedBox(width: 6),
              Text(
                socialAvailable ? 'Social SDK' : 'OAuth account',
                style: TextStyle(
                  color: context.surfaces.muted,
                  fontSize: FlucordType.caption,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: socialAvailable
              ? const Column(
                  children: [
                    DiscordActivityInviteStrip(),
                    Expanded(child: DiscordFriendDirectory()),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AccountProfileCard(account: account),
                          const SizedBox(height: 20),
                          const DiscordSocialSdkStatusPanel(),
                          const SizedBox(height: 20),
                          OAuthConnectedAccountDirectory(
                            connections: account.connections,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _AccountProfileCard extends StatelessWidget {
  const _AccountProfileCard({required this.account});

  final DiscordOAuthAccount account;

  @override
  Widget build(BuildContext context) {
    final accent = account.accentColor == null
        ? context.surfaces.raised
        : Color(0xFF000000 | account.accentColor!);
    final metadata = <String>[
      if (account.isVerified) 'Verified',
      if (account.mfaEnabled) 'MFA enabled',
      ?account.locale,
      if (account.publicFlags > 0)
        'Badges 0x${account.publicFlags.toRadixString(16).toUpperCase()}',
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border.all(color: context.surfaces.border),
        borderRadius: FlucordRadius.medium,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('oauth-account-profile-banner'),
                height: 92,
                child: RemoteIdentityImage(
                  url: account.bannerUrl,
                  fallback: ColoredBox(color: accent),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 36, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlucordTextRole.heading.style,
                          ),
                        ),
                        if (account.isVerified)
                          Tooltip(
                            message: 'Verified Discord account',
                            child: FlucordIcon(
                              FlucordIcons.verified,
                              size: 17,
                              color: context.surfaces.success,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      account.usernameLabel,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: FlucordType.caption,
                      ),
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        metadata.join(' · '),
                        key: const ValueKey('oauth-account-profile-metadata'),
                        style: TextStyle(
                          color: context.surfaces.muted,
                          fontSize: FlucordType.caption,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      '${account.guildCount} servers · ${account.connectionCount} connected accounts',
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: FlucordType.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 16,
            top: 64,
            child: Container(
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.surfaces.inset,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: RemoteIdentityImage(
                  url: account.avatarUrl,
                  fallback: ColoredBox(
                    color: context.surfaces.raised,
                    child: const FlucordIcon(FlucordIcons.person, size: 24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the account sidebar, sized like a DM row in the channel
/// sidebar: 40 high, a 28 px avatar or a 16 px icon, the name in the label
/// role and a caption line under it.
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.leading,
    required this.label,
    required this.detail,
    this.selected = false,
    this.onTap,
    this.rowKey,
  });

  final Widget leading;
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  /// Names the row's tap target, which is what tests and the row's size go by.
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Padding(
      padding: const EdgeInsets.only(bottom: SidebarRowMetrics.rowGap),
      child: Material(
        color: selected ? surfaces.quietFill : Colors.transparent,
        borderRadius: FlucordRadius.control,
        child: InkWell(
          key: rowKey,
          borderRadius: FlucordRadius.control,
          onTap: onTap,
          child: Container(
            height: SidebarRowMetrics.personRowHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: SidebarRowMetrics.rowPadding,
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: SidebarRowMetrics.personAvatarSize,
                  child: Center(child: leading),
                ),
                const SizedBox(width: SidebarRowMetrics.iconGap),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlucordTextRole.label.style.copyWith(
                          color: selected ? surfaces.text : surfaces.muted,
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlucordTextRole.caption.style.copyWith(
                          color: surfaces.captionText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _presenceLabel(DiscordPresenceStatus status) => switch (status) {
  DiscordPresenceStatus.online => 'Online',
  DiscordPresenceStatus.idle => 'Idle',
  DiscordPresenceStatus.doNotDisturb => 'Do Not Disturb',
  DiscordPresenceStatus.offline => 'Offline',
  DiscordPresenceStatus.unknown => 'Direct Message',
};
