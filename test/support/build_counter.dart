import 'package:flutter/widgets.dart';

/// How many times each widget type built during a [countBuilds] call.
///
/// A first build counts, as does a rebuild from a parent or from `setState`.
final class WidgetBuilds {
  const WidgetBuilds._(this.byType);

  /// All the counts, for a type a test cannot name, such as a private widget.
  final Map<Type, int> byType;

  /// The builds of widgets of exactly the type [T].
  int of<T extends Widget>() => byType[T] ?? 0;
}

/// Runs [action] and counts the widget builds that happen while it runs.
///
/// It uses Flutter's own debug hook, so production code needs no change. The
/// hook is removed when [action] ends, as the test framework requires.
///
/// ```dart
/// final builds = await countBuilds(() => session.dispatch(event, data));
/// expect(builds.of<MessageItem>(), 0);
/// ```
Future<WidgetBuilds> countBuilds(Future<void> Function() action) async {
  final counts = <Type, int>{};
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, _) {
    final type = element.widget.runtimeType;
    counts[type] = (counts[type] ?? 0) + 1;
  };
  try {
    await action();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return WidgetBuilds._(counts);
}
