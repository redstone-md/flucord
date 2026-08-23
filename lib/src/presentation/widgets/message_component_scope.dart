import 'package:flutter/widgets.dart';

import '../../application/message_component_controller.dart';

/// Publishes the message component controller to the conversation pane.
final class MessageComponentScope
    extends InheritedNotifier<MessageComponentController> {
  const MessageComponentScope({
    required MessageComponentController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static MessageComponentController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessageComponentScope>()
          ?.notifier;

  static MessageComponentController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'MessageComponentScope is missing above this widget.',
    );
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static MessageComponentController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MessageComponentScope>()!.notifier!;

}
