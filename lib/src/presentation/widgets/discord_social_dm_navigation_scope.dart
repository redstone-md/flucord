import 'package:flutter/widgets.dart';

import '../../application/discord_social_dm_navigation_controller.dart';

final class DiscordSocialDmNavigationScope
    extends InheritedNotifier<DiscordSocialDmNavigationController> {
  const DiscordSocialDmNavigationScope({
    required DiscordSocialDmNavigationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DiscordSocialDmNavigationController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiscordSocialDmNavigationScope>();
    assert(
      scope != null,
      'DiscordSocialDmNavigationScope is missing above this widget.',
    );
    return scope!.notifier!;
  }
}
