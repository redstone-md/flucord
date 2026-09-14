import 'package:flutter/widgets.dart';

import '../../application/discord_social_activity_controller.dart';

final class DiscordSocialActivityScope
    extends InheritedNotifier<DiscordSocialActivityController> {
  const DiscordSocialActivityScope({
    required DiscordSocialActivityController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DiscordSocialActivityController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DiscordSocialActivityScope>()
          ?.notifier;
}
