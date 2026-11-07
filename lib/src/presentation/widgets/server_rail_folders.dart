part of 'server_rail.dart';

/// Builds the rail's entries: lone servers and folders, each one a drag
/// source and a set of drop zones when the list can be saved.
final class _RailLayout {
  const _RailLayout({
    required this.rail,
    required this.spaces,
    required this.activity,
    required this.selectedSpaceId,
    required this.onSelectSpace,
    required this.onOpenSpaceMenu,
    required this.onDrop,
    required this.onEditFolder,
    required this.isExpanded,
    required this.onToggleFolder,
  });

  final GuildRail rail;
  final Map<String, CommunitySpace> spaces;
  final Map<String, SpaceActivity> activity;
  final String selectedSpaceId;
  final ValueChanged<String> onSelectSpace;
  final void Function(String spaceId, Offset position)? onOpenSpaceMenu;

  /// Null where the list cannot be saved, which turns dragging off.
  final void Function(RailDragItem item, RailDropTarget target)? onDrop;
  final void Function(int folderId, FolderSettings settings)? onEditFolder;
  final bool Function(int folderId) isExpanded;
  final ValueChanged<int> onToggleFolder;

  /// Every entry, plus a zone after the last one while dragging is on, where
  /// a drop goes to the end of the list.
  int get itemCount => rail.shown.length + (onDrop == null ? 0 : 1);

  Widget entry(BuildContext context, int index) {
    if (index == rail.shown.length) {
      return _DropZones(
        onDrop: onDrop,
        zones: [_Zone(RailDropAt(index), edge: _ZoneEdge.top)],
        child: const SizedBox(height: RailMetrics.tile),
      );
    }
    final entry = rail.shown[index];
    final folderId = entry.id;
    if (folderId == null) {
      final guildId = entry.guildIds.single;
      return _DropZones(
        onDrop: onDrop,
        zones: [
          _Zone(RailDropAt(index), edge: _ZoneEdge.top),
          _Zone(RailDropOnto(guildId)),
          _Zone(RailDropAt(index + 1), edge: _ZoneEdge.bottom),
        ],
        child: _draggable(DraggedGuild(guildId), _guild(guildId)),
      );
    }
    final colour = _folderColour(entry, context.surfaces.brand);
    final folder = _folderTile(entry, colour);
    if (!isExpanded(folderId)) {
      return _DropZones(
        onDrop: onDrop,
        zones: [
          _Zone(RailDropAt(index), edge: _ZoneEdge.top),
          _Zone(RailDropAt(entry.guildIds.length, folderId: folderId)),
          _Zone(RailDropAt(index + 1), edge: _ZoneEdge.bottom),
        ],
        child: _draggable(DraggedFolder(folderId), folder),
      );
    }
    final ids = entry.guildIds;
    return Padding(
      padding: const EdgeInsets.only(bottom: RailMetrics.gap),
      child: Center(
        child: DecoratedBox(
          key: ValueKey('space-folder-open-$folderId'),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.16),
            borderRadius: FlucordRadius.large,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DropZones(
                onDrop: onDrop,
                zones: [
                  _Zone(RailDropAt(index), edge: _ZoneEdge.top),
                  _Zone(RailDropAt(ids.length, folderId: folderId)),
                  _Zone(
                    RailDropAt(0, folderId: folderId),
                    edge: _ZoneEdge.bottom,
                  ),
                ],
                child: _draggable(DraggedFolder(folderId), folder),
              ),
              for (var at = 0; at < ids.length; at++)
                _DropZones(
                  onDrop: onDrop,
                  zones: [
                    _Zone(
                      RailDropAt(at, folderId: folderId),
                      edge: _ZoneEdge.top,
                    ),
                    _Zone(
                      RailDropAt(at + 1, folderId: folderId),
                      edge: _ZoneEdge.bottom,
                    ),
                  ],
                  child: _draggable(DraggedGuild(ids[at]), _guild(ids[at])),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The tile of [guildId]. [GuildRail.shown] holds only servers in
  /// [spaces], so the empty box is never drawn in practice.
  Widget _guild(String guildId) => switch (spaces[guildId]) {
    final space? => _SpaceButton(
      space: space,
      selected: space.id == selectedSpaceId,
      activity: activity[space.id] ?? SpaceActivity.none,
      onPressed: () => onSelectSpace(space.id),
      onOpenMenu: switch (onOpenSpaceMenu) {
        final open? => (position) => open(space.id, position),
        null => null,
      },
    ),
    null => const SizedBox.shrink(),
  };

  Widget _folderTile(GuildFolder folder, Color colour) {
    final folderId = folder.id!;
    final open = isExpanded(folderId);
    final members = [for (final id in folder.guildIds) ?spaces[id]];
    final edit = onEditFolder;
    return _FolderTile(
      name: _folderName(folder, members),
      members: members,
      colour: colour,
      open: open,
      // An open folder leaves the marks to its servers.
      selected: !open && folder.guildIds.contains(selectedSpaceId),
      activity: open
          ? SpaceActivity.none
          : SpaceActivity.folded([
              for (final id in folder.guildIds)
                activity[id] ?? SpaceActivity.none,
            ]),
      onPressed: () => onToggleFolder(folderId),
      onEdit: edit == null ? null : (settings) => edit(folderId, settings),
      folder: folder,
    );
  }

  Widget _draggable(RailDragItem item, Widget tile) {
    final padded = Padding(
      padding: const EdgeInsets.only(bottom: RailMetrics.gap),
      child: tile,
    );
    if (onDrop == null) return padded;
    return Draggable<RailDragItem>(
      data: item,
      feedback: Material(
        type: MaterialType.transparency,
        child: Opacity(opacity: 0.8, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: padded),
      child: padded,
    );
  }
}

/// The folder's own colour, or [fallback], the brand colour, for none.
Color _folderColour(GuildFolder folder, Color fallback) =>
    switch (folder.colour) {
      final rgb? => Color(DiscordRgb(rgb).opaque),
      null => fallback,
    };

/// The folder's name, or its servers' names when it has none, as Discord
/// labels it.
String _folderName(GuildFolder folder, List<CommunitySpace> members) =>
    switch (folder.name) {
      final name? when name.isNotEmpty => name,
      _ => members.map((space) => space.name).join(', '),
    };

enum _ZoneEdge { top, centre, bottom }

/// One part of a slot a drag can let go over.
final class _Zone {
  const _Zone(this.target, {this.edge = _ZoneEdge.centre});

  final RailDropTarget target;
  final _ZoneEdge edge;
}

/// Lays drop [zones] over [child], top to bottom, with the centre one twice
/// as tall as an edge. Without [onDrop] it is [child] alone.
class _DropZones extends StatelessWidget {
  const _DropZones({
    required this.onDrop,
    required this.zones,
    required this.child,
  });

  final void Function(RailDragItem item, RailDropTarget target)? onDrop;
  final List<_Zone> zones;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final drop = onDrop;
    if (drop == null) return child;
    final mark = context.surfaces.brand;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Column(
            children: [
              for (final zone in zones)
                Expanded(
                  flex: zone.edge == _ZoneEdge.centre ? 2 : 1,
                  child: DragTarget<RailDragItem>(
                    onWillAcceptWithDetails: (details) =>
                        GuildRail.accepts(details.data, zone.target),
                    onAcceptWithDetails: (details) =>
                        drop(details.data, zone.target),
                    // Never hit itself, so a tap still reaches the tile.
                    builder: (context, candidates, _) => IgnorePointer(
                      child: candidates.isEmpty
                          ? const SizedBox.expand()
                          : _DropMark(edge: zone.edge, colour: mark),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where a drag would land: a line between two tiles, or a ring round the
/// tile it would join.
class _DropMark extends StatelessWidget {
  const _DropMark({required this.edge, required this.colour});

  final _ZoneEdge edge;
  final Color colour;

  @override
  Widget build(BuildContext context) => switch (edge) {
    _ZoneEdge.centre => Center(
      child: Container(
        width: RailMetrics.tile + 4,
        height: RailMetrics.tile + 4,
        decoration: BoxDecoration(
          borderRadius: FlucordRadius.large,
          border: Border.all(color: colour, width: 2),
        ),
      ),
    ),
    _ZoneEdge.top || _ZoneEdge.bottom => Align(
      alignment: edge == _ZoneEdge.top
          ? Alignment.topCenter
          : Alignment.bottomCenter,
      child: Container(width: RailMetrics.tile, height: 2, color: colour),
    ),
  };
}

/// A folder's tile: a small grid of its servers while closed, the folder
/// glyph while open.
class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.name,
    required this.members,
    required this.colour,
    required this.open,
    required this.selected,
    required this.activity,
    required this.onPressed,
    required this.onEdit,
  });

  static const _preview = 16.0;
  static const _previewGap = 2.0;

  final GuildFolder folder;
  final String name;
  final List<CommunitySpace> members;
  final Color colour;
  final bool open;
  final bool selected;
  final SpaceActivity activity;
  final VoidCallback onPressed;
  final ValueChanged<FolderSettings>? onEdit;

  @override
  Widget build(BuildContext context) {
    final edit = onEdit;
    final folderId = folder.id!;
    return _SpaceTile(
      spaceId: 'folder-$folderId',
      tileKey: ValueKey('space-folder-$folderId'),
      name: name,
      selected: selected,
      activity: activity,
      onPressed: onPressed,
      onOpenMenu: edit == null
          ? null
          : (position) => unawaited(_openMenu(context, position, edit)),
      color: colour.withValues(alpha: open ? 0 : 0.4),
      activeColor: colour.withValues(alpha: open ? 0.16 : 0.56),
      builder: (context, _) => open
          ? Center(
              child: FlucordIcon(
                FlucordIcons.folder,
                size: RailMetrics.glyph,
                color: colour,
              ),
            )
          : Center(
              child: Wrap(
                spacing: _previewGap,
                runSpacing: _previewGap,
                children: [
                  for (final space in members.take(4))
                    ClipRRect(
                      borderRadius: FlucordRadius.small,
                      child: SizedBox.square(
                        dimension: _preview,
                        child: RemoteIdentityImage(
                          url: space.iconUrl,
                          animatesOnHover: false,
                          fallback: ColoredBox(color: Color(space.colorValue)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    Offset position,
    ValueChanged<FolderSettings> edit,
  ) => showFlucordActionMenu(
    context,
    position: position,
    items: [
      flucordMenuAction(
        'folder-settings',
        'Folder settings',
        FlucordIcons.settings,
        () => unawaited(_openSettings(context, edit)),
      ),
    ],
  );

  Future<void> _openSettings(
    BuildContext context,
    ValueChanged<FolderSettings> edit,
  ) async {
    final saved = await showDialog<FolderSettings>(
      context: context,
      builder: (_) =>
          FolderSettingsDialog(name: folder.name, colour: folder.colour),
    );
    if (saved != null) edit(saved);
  }
}
