import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../application/connection_controller.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

class ServerRail extends StatelessWidget {
  const ServerRail({
    required this.workspace,
    required this.selectedSpaceId,
    required this.onSelectSpace,
    required this.onToggleTheme,
    required this.onOpenConnections,
    required this.sessionMode,
    required this.isDark,
    super.key,
  });

  final ChatWorkspace workspace;
  final String selectedSpaceId;
  final ValueChanged<String> onSelectSpace;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenConnections;
  final SessionMode sessionMode;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final directSpaces = workspace.spaces.where(
      (space) => space.isDirectMessages,
    );
    final directSpace = directSpaces.isEmpty ? null : directSpaces.first;
    final guildSpaces = workspace.spaces
        .where((space) => !space.isDirectMessages)
        .toList(growable: false);
    return Container(
      key: const ValueKey('server-rail'),
      width: 72,
      decoration: BoxDecoration(
        color: context.surfaces.rail,
        border: Border(right: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _HomeButton(
            selected: directSpace?.id == selectedSpaceId,
            onPressed: directSpace == null
                ? null
                : () => onSelectSpace(directSpace.id),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, indent: 18, endIndent: 18),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: guildSpaces.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final space = guildSpaces[index];
                return _SpaceButton(
                  space: space,
                  selected: space.id == selectedSpaceId,
                  onPressed: () => onSelectSpace(space.id),
                );
              },
            ),
          ),
          IconButton(
            key: const ValueKey('open-connections'),
            onPressed: onOpenConnections,
            icon: Icon(
              sessionMode == SessionMode.discordBot
                  ? Icons.link
                  : Icons.link_outlined,
              color: sessionMode == SessionMode.discordBot
                  ? FlucordColors.brand
                  : null,
            ),
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

class _HomeButton extends StatelessWidget {
  const _HomeButton({required this.selected, required this.onPressed});

  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _RailButton(
    buttonKey: const ValueKey('space-direct-messages'),
    selected: selected,
    onPressed: onPressed,
    tooltip: onPressed == null ? 'Flucord' : 'Direct Messages',
    idleColor: context.surfaces.raised,
    activeColor: FlucordColors.brand,
    builder: (context, active) => Icon(
      Icons.forum_rounded,
      size: 21,
      color: active ? Colors.white : context.surfaces.muted,
    ),
  );
}

class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.space,
    required this.selected,
    required this.onPressed,
  });

  final CommunitySpace space;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _RailButton(
    buttonKey: ValueKey('space-${space.id}'),
    selected: selected,
    onPressed: onPressed,
    tooltip: space.name,
    idleColor: Color(space.colorValue).withValues(alpha: 0.62),
    activeColor: Color(space.colorValue),
    builder: (_, _) => RemoteIdentityImage(
      url: space.iconUrl,
      imageKey: ValueKey('space-icon-${space.id}'),
      fallback: Center(
        child: Text(
          space.monogram,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

typedef _RailButtonBuilder = Widget Function(BuildContext context, bool active);

class _RailButton extends StatefulWidget {
  const _RailButton({
    required this.buttonKey,
    required this.selected,
    required this.onPressed,
    required this.tooltip,
    required this.idleColor,
    required this.activeColor,
    required this.builder,
  });

  final Key buttonKey;
  final bool selected;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color idleColor;
  final Color activeColor;
  final _RailButtonBuilder builder;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final radius = BorderRadius.circular(active ? 14 : 22);
    return SizedBox(
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.selected)
            Positioned(
              left: 0,
              child: SizedBox(
                width: 3,
                height: 28,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          Tooltip(
            message: widget.tooltip,
            preferBelow: false,
            child: MouseRegion(
              onEnter: (_) {
                if (widget.onPressed != null) setState(() => _hovered = true);
              },
              onExit: (_) => setState(() => _hovered = false),
              child: Material(
                color: Colors.transparent,
                borderRadius: radius,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: widget.buttonKey,
                  onTap: widget.onPressed,
                  borderRadius: radius,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: active ? widget.activeColor : widget.idleColor,
                      borderRadius: radius,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.builder(context, active),
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
