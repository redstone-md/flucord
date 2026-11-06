import 'dart:math';

import 'package:collection/collection.dart';

/// One entry of the account's server list, as the `guild_folders` settings
/// group stores it. With an [id] it is a folder; without one it is a single
/// server outside any folder.
final class GuildFolder {
  const GuildFolder({required this.guildIds, this.id, this.name, this.colour});

  /// A server outside any folder.
  GuildFolder.lone(String guildId) : this(guildIds: [guildId]);

  final List<String> guildIds;
  final int? id;

  /// The name the person gave the folder, or null for none.
  final String? name;

  /// The folder's colour as 0xRRGGBB, or null for the default.
  final int? colour;

  bool get isFolder => id != null;

  GuildFolder _withGuilds(List<String> guildIds) =>
      GuildFolder(guildIds: guildIds, id: id, name: name, colour: colour);

  /// Compared by value, so the rail can tell a stored list that did not
  /// change from one that did.
  @override
  bool operator ==(Object other) =>
      other is GuildFolder &&
      other.id == id &&
      other.name == name &&
      other.colour == colour &&
      const ListEquality<String>().equals(other.guildIds, guildIds);

  @override
  int get hashCode => Object.hash(id, name, colour, Object.hashAll(guildIds));
}

/// What a drag on the rail carries.
sealed class RailDragItem {
  const RailDragItem();
}

final class DraggedGuild extends RailDragItem {
  const DraggedGuild(this.guildId);
  final String guildId;
}

final class DraggedFolder extends RailDragItem {
  const DraggedFolder(this.folderId);
  final int folderId;
}

/// Where a drag on the rail lets go.
sealed class RailDropTarget {
  const RailDropTarget();
}

/// Between two entries: at [index] of the top level, or of the folder
/// [folderId]. The index counts the entries as they are before the drop.
final class RailDropAt extends RailDropTarget {
  const RailDropAt(this.index, {this.folderId});
  final int index;
  final int? folderId;
}

/// Onto a server outside any folder, which makes a folder of the two.
final class RailDropOnto extends RailDropTarget {
  const RailDropOnto(this.guildId);
  final String guildId;
}

/// The server list as the rail draws it: every joined server once, in the
/// stored order, inside the stored folders.
final class GuildRail {
  const GuildRail._(this.entries);

  /// Lays the joined [guildIds] out by the [stored] folders.
  ///
  /// A server the settings do not list yet goes on top, as in Discord, in
  /// the order [guildIds] gives. Servers the account has left are dropped,
  /// and so is a folder left with none.
  factory GuildRail.arrange(List<GuildFolder> stored, List<String> guildIds) {
    final joined = guildIds.toSet();
    final placed = <String>{};
    final entries = <GuildFolder>[];
    for (final entry in stored) {
      final ids = [
        for (final id in entry.guildIds)
          if (joined.contains(id) && placed.add(id)) id,
      ];
      if (entry.isFolder) {
        if (ids.isNotEmpty) entries.add(entry._withGuilds(ids));
      } else {
        entries.addAll(ids.map(GuildFolder.lone));
      }
    }
    return GuildRail._([
      for (final id in guildIds)
        if (!placed.contains(id)) GuildFolder.lone(id),
      ...entries,
    ]);
  }

  final List<GuildFolder> entries;

  /// Whether [item] can land on [target]. Folders do not nest, and a server
  /// does not make a folder with itself.
  static bool accepts(RailDragItem item, RailDropTarget target) =>
      switch ((item, target)) {
        (DraggedFolder(), RailDropAt(folderId: null)) => true,
        (DraggedFolder(), _) => false,
        (DraggedGuild(:final guildId), RailDropOnto(guildId: final onto)) =>
          guildId != onto,
        (DraggedGuild(), _) => true,
      };

  /// The rail after [item] is dropped on [target], or this rail when the
  /// drop cannot happen.
  ///
  /// [newFolderId] names a folder the drop creates.
  GuildRail drop(
    RailDragItem item,
    RailDropTarget target, {
    int Function()? newFolderId,
  }) {
    if (!accepts(item, target)) return this;
    return switch ((item, target)) {
      (DraggedFolder(:final folderId), RailDropAt(:final index)) => _moveFolder(
        folderId,
        index,
      ),
      (
        DraggedGuild(:final guildId),
        RailDropAt(:final index, :final folderId),
      ) =>
        _moveGuild(guildId, index, folderId),
      (DraggedGuild(:final guildId), RailDropOnto(guildId: final onto)) =>
        _combine(guildId, onto, newFolderId ?? _randomFolderId),
      (DraggedFolder(), RailDropOnto()) => this,
    };
  }

  /// The rail with folder [folderId] renamed and recoloured. An empty name
  /// clears it.
  GuildRail editFolder(int folderId, {String? name, int? colour}) {
    final trimmed = name?.trim();
    return GuildRail._([
      for (final entry in entries)
        entry.id == folderId
            ? GuildFolder(
                guildIds: entry.guildIds,
                id: folderId,
                name: trimmed == null || trimmed.isEmpty ? null : trimmed,
                colour: colour,
              )
            : entry,
    ]);
  }

  GuildRail _moveFolder(int folderId, int index) {
    final from = entries.indexWhere((entry) => entry.id == folderId);
    if (from < 0) return this;
    final next = List.of(entries);
    final folder = next.removeAt(from);
    next.insert(_shifted(index, from).clamp(0, next.length), folder);
    return GuildRail._(next);
  }

  GuildRail _moveGuild(String guildId, int index, int? folderId) {
    if (!_holds(guildId)) return this;
    final next = _without(guildId);
    if (folderId == null) {
      next.insert(index.clamp(0, next.length), GuildFolder.lone(guildId));
    } else {
      final target = next.indexWhere((entry) => entry.id == folderId);
      if (target < 0) return this;
      final from = entries[target].guildIds.indexOf(guildId);
      final ids = List.of(next[target].guildIds);
      ids.insert(_shifted(index, from).clamp(0, ids.length), guildId);
      next[target] = next[target]._withGuilds(ids);
    }
    return GuildRail._withoutEmpty(next);
  }

  GuildRail _combine(String guildId, String targetId, int Function() newId) {
    final target = entries.indexWhere(
      (entry) => !entry.isFolder && entry.guildIds.single == targetId,
    );
    if (target < 0 || !_holds(guildId)) return this;
    final taken = {for (final entry in entries) ?entry.id};
    var id = newId();
    while (taken.contains(id)) {
      id = newId();
    }
    final next = _without(guildId)
      ..[target] = GuildFolder(guildIds: [targetId, guildId], id: id);
    return GuildRail._withoutEmpty(next);
  }

  bool _holds(String guildId) =>
      entries.any((entry) => entry.guildIds.contains(guildId));

  /// The entries with [guildId] taken out. An entry left empty keeps its
  /// place, so an index into the top level still counts it.
  List<GuildFolder> _without(String guildId) => [
    for (final entry in entries)
      entry.guildIds.contains(guildId)
          ? entry._withGuilds([
              for (final id in entry.guildIds)
                if (id != guildId) id,
            ])
          : entry,
  ];

  factory GuildRail._withoutEmpty(List<GuildFolder> entries) => GuildRail._([
    for (final entry in entries)
      if (entry.guildIds.isNotEmpty) entry,
  ]);

  /// [index], counted with the item at [from] still in the list, counted
  /// once it has been taken out. [from] is -1 when the item was elsewhere.
  static int _shifted(int index, int from) =>
      from >= 0 && from < index ? index - 1 : index;

  /// Discord gives a new folder a random id that fits in 32 bits.
  static int _randomFolderId() => Random().nextInt(1 << 32);
}
