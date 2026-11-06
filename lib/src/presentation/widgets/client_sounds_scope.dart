import 'package:flutter/widgets.dart';

import '../../application/client_sounds_controller.dart';

/// Publishes the client sound switch. Above the navigator, so the settings
/// dialog finds it.
final class ClientSoundsScope
    extends InheritedNotifier<ClientSoundsController> {
  const ClientSoundsScope({
    required ClientSoundsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ClientSoundsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClientSoundsScope>()?.notifier;
}
