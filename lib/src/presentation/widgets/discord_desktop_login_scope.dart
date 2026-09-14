import 'package:flutter/widgets.dart';

import '../../application/discord_desktop_login_controller.dart';

final class DiscordDesktopLoginScope
    extends InheritedNotifier<DiscordDesktopLoginController> {
  const DiscordDesktopLoginScope({
    required DiscordDesktopLoginController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DiscordDesktopLoginController of(BuildContext context) {
    final controller = context
        .dependOnInheritedWidgetOfExactType<DiscordDesktopLoginScope>()
        ?.notifier;
    assert(controller != null, 'DiscordDesktopLoginScope is missing.');
    return controller!;
  }
}
