import 'package:flutter/widgets.dart';

import '../../application/thread_membership_controller.dart';

/// Publishes the thread membership controller to the conversation pane.
final class ThreadMembershipScope
    extends InheritedNotifier<ThreadMembershipController> {
  const ThreadMembershipScope({
    required ThreadMembershipController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ThreadMembershipController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThreadMembershipScope>()
          ?.notifier;

  static ThreadMembershipController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'ThreadMembershipScope is missing above this widget.',
    );
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static ThreadMembershipController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ThreadMembershipScope>()!.notifier!;

}
