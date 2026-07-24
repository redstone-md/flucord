import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/discord_social_dm_controller.dart';
import '../../application/discord_social_sdk_controller.dart';
import '../../domain/discord_oauth.dart';
import '../../domain/discord_relationship.dart';
import '../../theme/flucord_theme.dart';
import 'discord_add_friend_dialog.dart';
import 'discord_activity_invite_strip.dart';
import 'discord_friend_directory.dart';
import 'discord_friends_scope.dart';
import 'discord_social_dm_navigation_scope.dart';
import 'discord_social_dm_scope.dart';
import 'discord_social_dm_view.dart';
import 'discord_social_sdk_status.dart';
import 'discord_social_sdk_scope.dart';
import 'oauth_account_footer.dart';
import 'oauth_connected_account_directory.dart';
import 'remote_identity_image.dart';

class OAuthAccountSidebar extends StatelessWidget {
  const OAuthAccountSidebar({required this.account, super.key});

  final DiscordOAuthAccount account;

  @override
  Widget build(BuildContext context) {
    final socialSdk = DiscordSocialSdkScope.of(context);
    final dmController = DiscordSocialDmScope.of(context);
    final navigation = DiscordSocialDmNavigationScope.of(context);
    return Container(
      key: const ValueKey('oauth-account-sidebar'),
      width: 236,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(right: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.surfaces.border),
              ),
            ),
            child: const Text(
              'Direct Messages',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
              children: [
                _SidebarItem(
                  icon: Icons.people_outline,
                  label: 'Friends',
                  detail:
                      socialSdk.state == DiscordSocialSdkControllerState.ready
                      ? 'Native social'
                      : 'Unavailable through OAuth',
                  selected: navigation.friendsSelected,
                  onTap: navigation.showFriends,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'DIRECT MESSAGES',
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (dmController.state == DiscordSocialDmLoadState.loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (dmController.state == DiscordSocialDmLoadState.ready &&
                    dmController.conversations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'No recent conversations',
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 10,
                      ),
                    ),
                  )
                else
                  for (final conversation in dmController.conversations)
                    _SidebarItem(
                      key: ValueKey(
                        'social-dm-conversation-${conversation.user.id}',
                      ),
                      icon: Icons.person_outline,
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
              const Icon(Icons.people_outline, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Friends',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
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
                    foregroundColor: FlucordColors.success,
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Add Friend'),
                ),
                const SizedBox(width: 10),
              ],
              Icon(
                socialReady ? Icons.people_outline : Icons.lock_outline,
                size: 16,
                color: socialReady
                    ? FlucordColors.success
                    : context.surfaces.muted,
              ),
              const SizedBox(width: 6),
              Text(
                socialAvailable ? 'Social SDK' : 'OAuth account',
                style: TextStyle(color: context.surfaces.muted, fontSize: 11),
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
        borderRadius: BorderRadius.circular(6),
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (account.isVerified)
                          const Tooltip(
                            message: 'Verified Discord account',
                            child: Icon(
                              Icons.verified_outlined,
                              size: 17,
                              color: FlucordColors.success,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      account.usernameLabel,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 11,
                      ),
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        metadata.join(' · '),
                        key: const ValueKey('oauth-account-profile-metadata'),
                        style: TextStyle(
                          color: context.surfaces.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      '${account.guildCount} servers · ${account.connectionCount} connected accounts',
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 10,
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
                    child: const Icon(Icons.person_outline, size: 24),
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

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.detail,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.surfaces.raised : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 18, color: context.surfaces.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
