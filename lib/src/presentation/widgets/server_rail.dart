import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../application/connection_controller.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';

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
    final currentMember = workspace.memberById(workspace.currentMemberId);
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: context.surfaces.canvas,
        border: Border(right: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _BrandMark(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, indent: 18, endIndent: 18),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: workspace.spaces.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final space = workspace.spaces[index];
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
                  ? FlucordColors.signal
                  : null,
            ),
            tooltip: 'Connections',
          ),
          IconButton(
            onPressed: onToggleTheme,
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode),
            tooltip: isDark ? 'Use light theme' : 'Use dark theme',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 4),
            child: Tooltip(
              message: '${currentMember.displayName} - ${currentMember.role}',
              child: MemberAvatar(member: currentMember, size: 38),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Flucord',
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: FlucordColors.signalDark,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Text(
          'F',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 21,
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Positioned(
              left: 0,
              child: Container(
                width: 3,
                height: 28,
                color: FlucordColors.signal,
              ),
            ),
          Tooltip(
            message: space.name,
            preferBelow: false,
            child: InkWell(
              key: ValueKey('space-${space.id}'),
              onTap: onPressed,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? Color(space.colorValue)
                      : Color(space.colorValue).withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(selected ? 8 : 22),
                ),
                alignment: Alignment.center,
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
          ),
        ],
      ),
    );
  }
}
