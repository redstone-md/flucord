import 'package:flutter/widgets.dart';

import '../../application/voice_controller.dart';

/// Publishes the voice controller to the conversation room and the settings
/// window.
///
/// The room and the devices belong to the machine's one voice connection, so
/// both surfaces reach the same controller here rather than having it threaded
/// down through the widget chain.
final class VoiceScope extends InheritedNotifier<VoiceController> {
  const VoiceScope({
    required VoiceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static VoiceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VoiceScope>()?.notifier;

  static VoiceController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'VoiceScope is missing above this widget.');
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static VoiceController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<VoiceScope>()!.notifier!;

}
