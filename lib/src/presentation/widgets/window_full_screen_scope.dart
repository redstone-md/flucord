import 'package:flutter/widgets.dart';

import '../../platform/window_full_screen.dart';

/// Publishes the window's full screen to the conversation pane. Absent, or
/// holding null, on a platform whose window cannot go full screen.
final class WindowFullScreenScope extends InheritedWidget {
  const WindowFullScreenScope({
    required this.fullScreen,
    required super.child,
    super.key,
  });

  final WindowFullScreen? fullScreen;

  static WindowFullScreen? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<WindowFullScreenScope>()
      ?.fullScreen;

  @override
  bool updateShouldNotify(WindowFullScreenScope oldWidget) =>
      fullScreen != oldWidget.fullScreen;
}
