import 'package:flutter/material.dart';

import '../../domain/discord_oauth.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import 'rail_tile.dart';
import 'remote_identity_image.dart';

class OAuthGuildRail extends StatelessWidget {
  const OAuthGuildRail({
    required this.account,
    required this.accountHomeSelected,
    required this.selectedGuildId,
    required this.onOpenAccountHome,
    required this.onSelectGuild,
    required this.onOpenConnections,
    required this.onToggleTheme,
    required this.isDark,
    super.key,
  });

  final DiscordOAuthAccount account;
  final bool accountHomeSelected;
  final String? selectedGuildId;
  final VoidCallback onOpenAccountHome;
  final ValueChanged<String> onSelectGuild;
  final VoidCallback onOpenConnections;
  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('oauth-guild-rail'),
      width: RailMetrics.width,
      decoration: BoxDecoration(color: context.surfaces.rail),
      child: Column(
        children: [
          const SizedBox(height: RailMetrics.gap),
          RailTile(
            tileKey: const ValueKey('oauth-account-home'),
            label: '${account.displayName}, account home',
            tooltip: 'Direct Messages / ${account.displayName}',
            onPressed: onOpenAccountHome,
            selected: accountHomeSelected,
            pill: accountHomeSelected ? RailPill.selected : RailPill.none,
            pillKey: const ValueKey('oauth-account-home-indicator'),
            color: context.surfaces.raised,
            builder: (_, _) => RemoteIdentityImage(
              url: account.avatarUrl,
              fallback: const Center(
                child: FlucordIcon(
                  FlucordIcons.person,
                  size: RailMetrics.glyph,
                ),
              ),
            ),
          ),
          const RailDivider(),
          Expanded(
            child: ListView.separated(
              itemCount: account.guilds.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: RailMetrics.gap),
              itemBuilder: (context, index) {
                final guild = account.guilds[index];
                final selected = guild.id == selectedGuildId;
                return RailTile(
                  tileKey: ValueKey('oauth-guild-${guild.id}'),
                  label: '${guild.name}, authorized server directory',
                  tooltip: guild.name,
                  onPressed: () => onSelectGuild(guild.id),
                  selected: selected,
                  pill: selected ? RailPill.selected : RailPill.none,
                  pillKey: ValueKey('oauth-guild-indicator-${guild.id}'),
                  color: context.surfaces.raised,
                  activeColor: context.surfaces.brand,
                  builder: (_, _) => RemoteIdentityImage(
                    url: guild.iconUrl,
                    fallback: RailMonogram(_guildMonogram(guild.name)),
                  ),
                );
              },
            ),
          ),
          IconButton(
            key: const ValueKey('open-oauth-workspace-connections'),
            onPressed: onOpenConnections,
            icon: FlucordIcon(
              FlucordIcons.link,
              color: context.surfaces.accentIcon,
            ),
            tooltip: 'Connections',
          ),
          RailThemeToggle(isDark: isDark, onPressed: onToggleTheme),
          const SizedBox(height: RailMetrics.gap),
        ],
      ),
    );
  }
}

String _guildMonogram(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  return words
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word.substring(0, 1).toUpperCase())
      .join();
}
