import 'package:flutter/widgets.dart';

import '../../application/go_live_controller.dart';

/// Publishes Go Live to the conversation pane.
final class GoLiveScope extends InheritedNotifier<GoLiveController> {
  const GoLiveScope({
    required GoLiveController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static GoLiveController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GoLiveScope>()?.notifier;

  static GoLiveController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'GoLiveScope is missing above this widget.');
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static GoLiveController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GoLiveScope>()!.notifier!;

}
