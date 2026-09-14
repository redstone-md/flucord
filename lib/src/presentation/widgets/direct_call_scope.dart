import 'package:flutter/widgets.dart';

import '../../application/direct_call_controller.dart';

/// Publishes the DM call controller to the conversation pane.
///
/// Absent in hosts with no call plane, such as a demo workspace or a bot
/// session, which is also how the call affordances stay off rather than
/// failing: [maybeOf] returns null and the header drops the call button. The
/// pane listens to the controller itself where it needs live call state, so
/// this is a plain [InheritedWidget] rather than a notifier scope.
final class DirectCallScope extends InheritedWidget {
  const DirectCallScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final DirectCallController? controller;

  @override
  bool updateShouldNotify(DirectCallScope oldWidget) =>
      oldWidget.controller != controller;

  static DirectCallController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DirectCallScope>()?.controller;
}
