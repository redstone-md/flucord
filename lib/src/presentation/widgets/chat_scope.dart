import 'package:flutter/widgets.dart';

import '../../application/chat_controller.dart';

/// Publishes the conversation controller to the conversation pane.
///
/// The pane resolves it here instead of receiving it through the widget chain,
/// and reads the per-channel state (typing, loading, history) straight from
/// it, so no piece of channel state travels as a constructor parameter.
final class ChatScope extends InheritedNotifier<ChatController> {
  const ChatScope({
    required ChatController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ChatController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatScope>()?.notifier;

  static ChatController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'ChatScope is missing above this widget.');
    return controller!;
  }

  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static ChatController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatScope>()!.notifier!;
}
