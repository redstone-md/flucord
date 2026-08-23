import 'package:flutter/widgets.dart';

import '../../application/workspace_controller.dart';

/// Publishes the workspace selection to the conversation pane.
///
/// The pane resolves it here instead of receiving it through the widget chain,
/// and reads the selection state (query, message target, voice surface) and
/// the panel toggles straight from it.
final class WorkspaceScope extends InheritedNotifier<WorkspaceController> {
  const WorkspaceScope({
    required WorkspaceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static WorkspaceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceScope>()?.notifier;

  static WorkspaceController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'WorkspaceScope is missing above this widget.');
    return controller!;
  }
}
