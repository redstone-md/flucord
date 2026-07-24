import 'package:flutter/material.dart';

import '../../application/discord_social_sdk_controller.dart';
import '../../domain/discord_oauth.dart';
import '../../theme/flucord_theme.dart';
import 'discord_friend_directory.dart';
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
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'CONNECTED ACCOUNTS · ${account.connectionCount}',
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final connection in account.connections.take(6))
                  _SidebarItem(
                    icon: Icons.link,
                    label: connection.name,
                    detail: connection.type,
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
    final socialAvailable = socialSdk.availability?.isReady ?? false;
    final socialReady = socialSdk.isAuthenticated;
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
              ? const DiscordFriendDirectory()
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
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  style: TextStyle(color: context.surfaces.muted, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
