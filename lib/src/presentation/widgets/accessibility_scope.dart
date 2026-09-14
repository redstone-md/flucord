import 'package:flutter/widgets.dart';

import '../../application/accessibility_controller.dart';

/// Publishes the accessibility dials to whatever draws for them.
///
/// A scope rather than a parameter threaded through the tree: the font scale
/// and the zoom belong to the whole client, and a widget deep in a pane
/// should not need six constructors between it and the controller to find
/// out whether animations are allowed to play.
final class AccessibilityScope
    extends InheritedNotifier<AccessibilityController> {
  const AccessibilityScope({
    required AccessibilityController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AccessibilityController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AccessibilityScope>()
      ?.notifier;
}
