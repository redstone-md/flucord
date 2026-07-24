import 'package:flutter/material.dart';

import '../../domain/discord_oauth.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

class OAuthGuildRail extends StatelessWidget {
  const OAuthGuildRail({
    required this.account,
    required this.selectedGuildId,
    required this.onSelectGuild,
    required this.onOpenConnections,
    required this.onToggleTheme,
    required this.isDark,
    super.key,
  });

  final DiscordOAuthAccount account;
  final String? selectedGuildId;
  final ValueChanged<String> onSelectGuild;
  final VoidCallback onOpenConnections;
  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('oauth-guild-rail'),
      width: 72,
      decoration: BoxDecoration(
        color: context.surfaces.rail,
        border: Border(right: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Tooltip(
            message: account.displayName,
            child: ClipOval(
              child: SizedBox.square(
                dimension: 44,
                child: RemoteIdentityImage(
                  url: account.avatarUrl,
                  fallback: ColoredBox(
                    color: context.surfaces.raised,
                    child: const Icon(Icons.person_outline, size: 21),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, indent: 18, endIndent: 18),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: account.guilds.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final guild = account.guilds[index];
                return _OAuthGuildRailButton(
                  guild: guild,
                  selected: guild.id == selectedGuildId,
                  onPressed: () => onSelectGuild(guild.id),
                );
              },
            ),
          ),
          IconButton(
            key: const ValueKey('open-oauth-workspace-connections'),
            onPressed: onOpenConnections,
            icon: const Icon(Icons.link, color: FlucordColors.brand),
            tooltip: 'Connections',
          ),
          IconButton(
            onPressed: onToggleTheme,
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode),
            tooltip: isDark ? 'Use light theme' : 'Use dark theme',
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _OAuthGuildRailButton extends StatefulWidget {
  const _OAuthGuildRailButton({
    required this.guild,
    required this.selected,
    required this.onPressed,
  });

  final DiscordOAuthGuild guild;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_OAuthGuildRailButton> createState() => _OAuthGuildRailButtonState();
}

class _OAuthGuildRailButtonState extends State<_OAuthGuildRailButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final radius = BorderRadius.circular(active ? 14 : 22);
    return Semantics(
      label: '${widget.guild.name}, authorized server directory',
      button: true,
      selected: widget.selected,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: SizedBox(
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.selected)
              Positioned(
                left: 0,
                child: SizedBox(
                  key: ValueKey('oauth-guild-indicator-${widget.guild.id}'),
                  width: 3,
                  height: 28,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            Tooltip(
              message: widget.guild.name,
              preferBelow: false,
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('oauth-guild-${widget.guild.id}'),
                    onTap: widget.onPressed,
                    borderRadius: radius,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: active
                            ? FlucordColors.brand
                            : context.surfaces.raised,
                        borderRadius: radius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: RemoteIdentityImage(
                        url: widget.guild.iconUrl,
                        fallback: Center(
                          child: Text(
                            _guildMonogram(widget.guild.name),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
