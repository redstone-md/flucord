import 'package:flutter/widgets.dart';

import '../../application/discord_social_dm_controller.dart';

final class DiscordSocialDmScope
    extends InheritedNotifier<DiscordSocialDmController> {
  const DiscordSocialDmScope({
    required DiscordSocialDmController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DiscordSocialDmController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiscordSocialDmScope>();
    assert(scope != null, 'DiscordSocialDmScope is missing above this widget.');
    return scope!.notifier!;
  }
}
