import 'package:flutter/widgets.dart';

import '../../application/soundboard_controller.dart';

/// Publishes the soundboard controller to the conversation pane.
final class SoundboardScope extends InheritedNotifier<SoundboardController> {
  const SoundboardScope({
    required SoundboardController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static SoundboardController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SoundboardScope>()?.notifier;

  static SoundboardController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'SoundboardScope is missing above this widget.');
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static SoundboardController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SoundboardScope>()!.notifier!;

}
