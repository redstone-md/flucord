import 'package:flutter/widgets.dart';

import '../../application/keybind_controller.dart';

/// Publishes the keybinds to the settings window.
///
/// Same shape and same reason as the other scopes: the settings gear sits in
/// the rail, several layers from whatever owns the controller.
final class KeybindScope extends InheritedNotifier<KeybindController> {
  const KeybindScope({
    required KeybindController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static KeybindController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KeybindScope>()?.notifier;
}
