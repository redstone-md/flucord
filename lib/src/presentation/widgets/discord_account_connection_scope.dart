import 'package:flutter/widgets.dart';

import '../../application/discord_account_connection_controller.dart';

final class DiscordAccountConnectionScope
    extends InheritedNotifier<DiscordAccountConnectionController> {
  const DiscordAccountConnectionScope({
    required DiscordAccountConnectionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DiscordAccountConnectionController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'DiscordAccountConnectionScope is missing above this widget.',
    );
    return controller!;
  }

  static DiscordAccountConnectionController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DiscordAccountConnectionScope>()
          ?.notifier;
}
