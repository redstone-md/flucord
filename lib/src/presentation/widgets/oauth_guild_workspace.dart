import 'package:flutter/material.dart';

import '../../application/oauth_guild_membership_controller.dart';
import '../../domain/discord_oauth.dart';
import '../../theme/flucord_theme.dart';
import 'oauth_account_footer.dart';
import 'oauth_account_home.dart';
import 'oauth_guild_membership_panel.dart';
import 'oauth_guild_rail.dart';

class OAuthGuildWorkspace extends StatelessWidget {
  const OAuthGuildWorkspace({
    required this.account,
    required this.accountHomeSelected,
    required this.membershipController,
    required this.selectedGuildId,
    required this.onSelectGuild,
    required this.onOpenAccountHome,
    required this.onOpenConnections,
    required this.onToggleTheme,
    required this.isDark,
    super.key,
  });

  final DiscordOAuthAccount account;
  final bool accountHomeSelected;
  final OAuthGuildMembershipController membershipController;
  final String? selectedGuildId;
  final ValueChanged<String> onSelectGuild;
  final VoidCallback onOpenAccountHome;
  final VoidCallback onOpenConnections;
  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final guild = accountHomeSelected
        ? null
        : _selectedGuild(account.guilds, selectedGuildId);
    return Scaffold(
      key: const ValueKey('oauth-guild-workspace'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidebar = constraints.maxWidth >= 700;
          return Row(
            children: [
              OAuthGuildRail(
                account: account,
                accountHomeSelected: accountHomeSelected,
                selectedGuildId: guild?.id,
                onOpenAccountHome: onOpenAccountHome,
                onSelectGuild: onSelectGuild,
                onOpenConnections: onOpenConnections,
                onToggleTheme: onToggleTheme,
                isDark: isDark,
              ),
              if (showSidebar)
                if (accountHomeSelected)
                  OAuthAccountSidebar(account: account)
                else
                  _OAuthGuildSidebar(
                    account: account,
                    guild: guild,
                    membershipController: membershipController,
                  ),
              Expanded(
                child: accountHomeSelected
                    ? OAuthAccountHomeView(account: account)
                    : _OAuthMessageBoundary(
                        guild: guild,
                        onOpenConnections: onOpenConnections,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static DiscordOAuthGuild? _selectedGuild(
    List<DiscordOAuthGuild> guilds,
    String? selectedGuildId,
  ) {
    for (final guild in guilds) {
      if (guild.id == selectedGuildId) return guild;
    }
    return guilds.isEmpty ? null : guilds.first;
  }
}

class _OAuthGuildSidebar extends StatelessWidget {
  const _OAuthGuildSidebar({
    required this.account,
    required this.guild,
    required this.membershipController,
  });

  final DiscordOAuthAccount account;
  final DiscordOAuthGuild? guild;
  final OAuthGuildMembershipController membershipController;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('oauth-guild-sidebar'),
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
            child: Text(
              guild?.name ?? 'Discord servers',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 20, 16, 16),
              children: [
                Text(
                  'CHANNELS',
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: context.surfaces.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        guild == null
                            ? 'No authorized servers'
                            : 'Channel directory unavailable through OAuth',
                        style: TextStyle(
                          color: context.surfaces.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                if (guild case final selectedGuild?) ...[
                  const SizedBox(height: 24),
                  Text(
                    'YOUR SERVER PROFILE',
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OAuthGuildMembershipPanel(
                    controller: membershipController,
                    account: account,
                    guild: selectedGuild,
                  ),
                ],
              ],
            ),
          ),
          OAuthAccountFooter(account: account),
        ],
      ),
    );
  }
}

class _OAuthMessageBoundary extends StatelessWidget {
  const _OAuthMessageBoundary({
    required this.guild,
    required this.onOpenConnections,
  });

  final DiscordOAuthGuild? guild;
  final VoidCallback onOpenConnections;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('oauth-guild-message-boundary'),
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.surfaces.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: context.surfaces.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  guild?.name ?? 'Authorized servers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'OAuth directory',
                style: TextStyle(color: context.surfaces.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    guild == null ? Icons.dns_outlined : Icons.lock_outline,
                    size: 32,
                    color: context.surfaces.muted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    guild == null
                        ? 'No authorized servers'
                        : 'Messages unavailable for this server',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    guild == null
                        ? 'Discord returned an empty guild directory.'
                        : 'The public OAuth scope exposes this server, but not its channels or message history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  if (guild != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _guildMetadata(guild!),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: onOpenConnections,
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Connections'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _guildMetadata(DiscordOAuthGuild guild) {
  final values = <String>[
    if (guild.isOwner) 'Owner' else if (guild.isAdministrator) 'Administrator',
    if (guild.approximateMemberCount case final count?) '$count members',
    if (guild.approximatePresenceCount case final count?) '$count online',
  ];
  return values.isEmpty ? 'Authorized server' : values.join(' · ');
}
