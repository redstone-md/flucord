import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/discord_rgb.dart';
import '../../domain/guild_folders.dart';
import '../../domain/workspace_activity.dart';
import '../../application/connection_controller.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

import 'activity_label.dart';
import 'count_badge.dart';
import 'flucord_menu.dart';
import 'folder_settings_dialog.dart';
import 'rail_tile.dart';

part 'server_rail_folders.dart';

class ServerRail extends StatefulWidget {
  const ServerRail({
    required this.spaces,
    required this.activity,
    required this.selectedSpaceId,
    required this.onSelectSpace,
    required this.onToggleTheme,
    required this.onOpenConnections,
    required this.sessionMode,
    required this.isDark,
    this.folders = const [],
    this.onArrange,
    this.onAddServer,
    this.onOpenSpaceMenu,
    super.key,
  });

  final List<CommunitySpace> spaces;

  /// What each space has waiting, already rolled up. Taken ready-made rather
  /// than rolled up here so the rail's inputs are small enough to compare,
  /// which is what lets the shell keep the rail across a rebuild that did not
  /// move any pip.
  final Map<String, SpaceActivity> activity;

  final String selectedSpaceId;
  final ValueChanged<String> onSelectSpace;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenConnections;
  final SessionMode sessionMode;
  final bool isDark;

  /// The account's stored folders and server order.
  final List<GuildFolder> folders;

  /// Saves a new server list, or null where nothing can be saved. Servers
  /// and folders can be dragged and folders edited only with it.
  final ValueChanged<List<GuildFolder>>? onArrange;

  /// Opens the add-server surface, or null on a transport that cannot join,
  /// create or leave anything. The button is hidden rather than disabled:
  /// a plus that can do nothing is a lie about what the app offers.
  final VoidCallback? onAddServer;

  /// Opens the menu of a server at a global position, on a right click.
  final void Function(String spaceId, Offset position)? onOpenSpaceMenu;

  @override
  State<ServerRail> createState() => _ServerRailState();
}

class _ServerRailState extends State<ServerRail> {
  /// The folders shown open. Kept on this device only, as Discord does.
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final spaces = widget.spaces;
    final directSpaces = spaces.where((space) => space.isDirectMessages);
    final directSpace = directSpaces.isEmpty ? null : directSpaces.first;
    final guildSpaces = {
      for (final space in spaces)
        if (!space.isDirectMessages) space.id: space,
    };
    final rail = GuildRail.arrange(widget.folders, guildSpaces.keys.toList());
    final arrange = widget.onArrange;
    final layout = _RailLayout(
      rail: rail,
      spaces: guildSpaces,
      activity: widget.activity,
      selectedSpaceId: widget.selectedSpaceId,
      onSelectSpace: widget.onSelectSpace,
      onOpenSpaceMenu: widget.onOpenSpaceMenu,
      onDrop: arrange == null
          ? null
          : (item, target) {
              final next = rail.drop(item, target);
              if (!listEquals(next.entries, rail.entries)) {
                arrange(next.entries);
              }
            },
      onEditFolder: arrange == null
          ? null
          : (folderId, name, colour) => arrange(
              rail.editFolder(folderId, name: name, colour: colour).entries,
            ),
      isExpanded: _expanded.contains,
      onToggleFolder: (folderId) => setState(() {
        if (!_expanded.remove(folderId)) _expanded.add(folderId);
      }),
    );
    return Container(
      key: const ValueKey('server-rail'),
      width: RailMetrics.width,
      decoration: BoxDecoration(color: context.surfaces.rail),
      child: Column(
        children: [
          const SizedBox(height: RailMetrics.gap),
          _HomeButton(
            selected: directSpace?.id == widget.selectedSpaceId,
            activity: directSpace == null
                ? SpaceActivity.none
                : widget.activity[directSpace.id] ?? SpaceActivity.none,
            onPressed: directSpace == null
                ? null
                : () => widget.onSelectSpace(directSpace.id),
          ),
          const RailDivider(),
          Expanded(
            child: ListView.builder(
              // Room for the badge that hangs below the last tile.
              padding: const EdgeInsets.only(bottom: RailMetrics.gap),
              itemCount: layout.itemCount,
              itemBuilder: layout.entry,
            ),
          ),
          if (widget.onAddServer case final onAddServer?)
            Padding(
              padding: const EdgeInsets.only(bottom: RailMetrics.gap),
              child: _AddServerButton(onPressed: onAddServer),
            ),
          IconButton(
            key: const ValueKey('open-connections'),
            onPressed: widget.onOpenConnections,
            icon: FlucordIcon(
              FlucordIcons.link,
              color: widget.sessionMode == SessionMode.discord
                  ? context.surfaces.accentIcon
                  : null,
            ),
            tooltip: 'Connections',
          ),
          RailThemeToggle(
            isDark: widget.isDark,
            onPressed: widget.onToggleTheme,
          ),
          const SizedBox(height: RailMetrics.gap),
        ],
      ),
    );
  }
}

/// The add-server entry at the foot of the space list: an outlined tile, so
/// it reads as an action rather than as one more server.
class _AddServerButton extends StatelessWidget {
  const _AddServerButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => RailTile(
    tileKey: const ValueKey('add-server'),
    label: 'Add a server',
    onPressed: onPressed,
    activeColor: context.surfaces.control,
    builder: (context, active) => FlucordIcon(
      FlucordIcons.add,
      size: RailMetrics.glyph,
      color: active ? context.surfaces.text : context.surfaces.muted,
    ),
  );
}

class _HomeButton extends StatelessWidget {
  const _HomeButton({
    required this.selected,
    required this.activity,
    required this.onPressed,
  });

  final bool selected;
  final SpaceActivity activity;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _SpaceTile(
    spaceId: CommunitySpace.directMessagesId,
    tileKey: const ValueKey('space-direct-messages'),
    name: onPressed == null ? 'Flucord' : 'Direct Messages',
    selected: selected,
    activity: activity,
    onPressed: onPressed,
    color: context.surfaces.raised,
    activeColor: context.surfaces.brand,
    builder: (context, active) => FlucordIcon(
      FlucordIcons.directMessages,
      size: RailMetrics.glyph,
      color: active
          ? Theme.of(context).colorScheme.onPrimary
          : context.surfaces.muted,
    ),
  );
}

class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.space,
    required this.selected,
    required this.activity,
    required this.onPressed,
    required this.onOpenMenu,
  });

  final CommunitySpace space;
  final bool selected;
  final SpaceActivity activity;
  final VoidCallback onPressed;
  final ValueChanged<Offset>? onOpenMenu;

  @override
  Widget build(BuildContext context) => _SpaceTile(
    spaceId: space.id,
    tileKey: ValueKey('space-${space.id}'),
    name: space.name,
    selected: selected,
    activity: activity,
    onPressed: onPressed,
    onOpenMenu: onOpenMenu,
    color: Color(space.colorValue).withValues(alpha: 0.62),
    activeColor: Color(space.colorValue),
    builder: (_, _) => RemoteIdentityImage(
      url: space.iconUrl,
      imageKey: ValueKey('space-icon-${space.id}'),
      animatesOnHover: true,
      fallback: RailMonogram(space.monogram),
    ),
  );
}

/// A space on the rail: its pill shows whether it is open or unread, and its
/// badge counts the mentions waiting there.
class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.spaceId,
    required this.tileKey,
    required this.name,
    required this.selected,
    required this.activity,
    required this.onPressed,
    required this.color,
    required this.activeColor,
    required this.builder,
    this.onOpenMenu,
  });

  final String spaceId;
  final Key tileKey;
  final String name;
  final bool selected;
  final SpaceActivity activity;
  final VoidCallback? onPressed;
  final ValueChanged<Offset>? onOpenMenu;
  final Color color;
  final Color activeColor;
  final Widget Function(BuildContext context, bool active) builder;

  @override
  Widget build(BuildContext context) => RailTile(
    key: ValueKey('space-semantics-$spaceId'),
    tileKey: tileKey,
    label: activityLabel(
      name,
      mentionCount: activity.mentionCount,
      muted: activity.muted,
      unread: activity.hasUnread,
    ),
    onPressed: onPressed,
    onOpenMenu: onOpenMenu,
    selected: selected,
    pill: selected
        ? RailPill.selected
        : activity.hasUnread
        ? RailPill.unread
        : RailPill.none,
    pillKey: ValueKey('space-indicator-$spaceId'),
    color: color,
    activeColor: activeColor,
    dimmed: activity.muted,
    badge: activity.mentionCount > 0
        ? CountBadge(
            key: ValueKey('space-mention-$spaceId'),
            count: activity.mentionCount,
            ring: context.surfaces.rail,
          )
        : null,
    builder: builder,
  );
}
