import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Holds on to a subtree until one of [dependencies] changes.
///
/// The shell is rebuilt whenever the chat controller notifies, which on an
/// account with a couple of hundred spaces is every frame, while most of what
/// the shell holds does not change with most events. Handing Flutter back the
/// same widget instance lets it skip that subtree — its build and its layout
/// both.
///
/// [dependencies] must name everything [builder] reads. Anything left out goes
/// stale, which is the trade any memoised value makes. The same applies to
/// callbacks built inside [builder]: one that captures a value instead of
/// reading it when it fires will keep firing with the captured one.
///
/// Lists, sets and maps are compared by their contents, one level deep, so a
/// freshly built collection of unchanged items counts as unchanged — which is
/// the common case, since the workspace hands out a new list per change while
/// the entries inside it stay put.
class CachedSubtree extends StatefulWidget {
  const CachedSubtree({
    required this.dependencies,
    required this.builder,
    super.key,
  });

  final List<Object?> dependencies;
  final WidgetBuilder builder;

  @override
  State<CachedSubtree> createState() => _CachedSubtreeState();
}

class _CachedSubtreeState extends State<CachedSubtree> {
  List<Object?>? _dependencies;
  Widget? _child;

  @override
  Widget build(BuildContext context) {
    final cached = _child;
    if (cached != null && _matchesLast(widget.dependencies)) return cached;
    _dependencies = List.of(widget.dependencies, growable: false);
    return _child = widget.builder(context);
  }

  bool _matchesLast(List<Object?> next) {
    final previous = _dependencies;
    if (previous == null || previous.length != next.length) return false;
    for (var index = 0; index < next.length; index++) {
      if (!_same(previous[index], next[index])) return false;
    }
    return true;
  }

  static bool _same(Object? left, Object? right) => switch ((left, right)) {
    (final List<Object?> a, final List<Object?> b) => listEquals(a, b),
    (final Set<Object?> a, final Set<Object?> b) => setEquals(a, b),
    (final Map<Object?, Object?> a, final Map<Object?, Object?> b) => mapEquals(
      a,
      b,
    ),
    _ => left == right,
  };
}
