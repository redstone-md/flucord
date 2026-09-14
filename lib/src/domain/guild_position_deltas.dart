part of 'guild_management.dart';

/// One `{id, position}` pair, before it is wrapped for a specific route.
typedef PositionDelta = ({String id, int position});

/// The renderer's `calculatePositionDeltas`, ported verbatim.
///
/// Two things about it are load-bearing and neither is obvious:
///
/// * An entry is emitted only when the item genuinely moved, and "moved" is
///   judged on **both** its recorded position and its index in the old
///   ordering. Position alone is not enough: a guild whose roles all carry
///   position 0 — which Discord does produce — would then look untouched no
///   matter how the list was dragged. Index alone is not enough either, because
///   a list can be rebuilt in the same order from records whose positions the
///   server has since renumbered.
/// * Sending the no-op entries anyway is what makes rows visibly jump after a
///   save: the server applies every entry it is given, and two items sharing a
///   position resolve in whatever order the array happened to list them.
///
/// [ascending] is the natural direction for channels, where position 0 is the
/// top of the list. Roles run the other way — position 0 is `@everyone`, at the
/// bottom — so their pass is descending and the result is reversed, which is
/// what puts the lowest role first in the array.
List<PositionDelta> calculatePositionDeltas<T>({
  required List<T> oldOrdering,
  required List<T> newOrdering,
  required String Function(T item) idOf,
  required int Function(T item) positionOf,
  required bool ascending,
}) {
  final oldIndexes = <String, int>{};
  for (var index = 0; index < oldOrdering.length; index++) {
    oldIndexes[idOf(oldOrdering[index])] = index;
  }
  final length = newOrdering.length;
  final deltas = <PositionDelta>[];
  for (var index = 0; index < length; index++) {
    final item = newOrdering[index];
    final id = idOf(item);
    final target = ascending ? index : length - 1 - index;
    final oldIndex = oldIndexes[id];
    if (oldIndex == target && positionOf(item) == target) continue;
    deltas.add((id: id, position: target));
  }
  return ascending ? deltas : deltas.reversed.toList(growable: false);
}
