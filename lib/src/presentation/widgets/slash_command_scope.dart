import 'package:flutter/widgets.dart';

import '../../application/slash_command_controller.dart';

/// Publishes the application commands to the conversation pane.
final class SlashCommandScope extends InheritedNotifier<SlashCommandController> {
  const SlashCommandScope({
    required SlashCommandController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static SlashCommandController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlashCommandScope>()?.notifier;

  static SlashCommandController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'SlashCommandScope is missing above this widget.',
    );
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static SlashCommandController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SlashCommandScope>()!.notifier!;

}
