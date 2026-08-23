import 'package:flutter/widgets.dart';

import '../../application/stage_controller.dart';

/// Publishes the stage controller to the conversation pane.
final class StageScope extends InheritedNotifier<StageController> {
  const StageScope({
    required StageController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static StageController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StageScope>()?.notifier;

  static StageController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'StageScope is missing above this widget.');
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static StageController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StageScope>()!.notifier!;

}
