import 'package:flutter/widgets.dart';

import '../../application/voice_controller.dart';

/// Publishes voice to the settings window.
///
/// The devices belong to the machine, so the settings screen reaches them the
/// same way it reaches the themes, rather than having them threaded down
/// through the shell.
final class VoiceScope extends InheritedNotifier<VoiceController> {
  const VoiceScope({
    required VoiceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static VoiceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VoiceScope>()?.notifier;
}
