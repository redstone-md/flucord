import 'package:flutter/widgets.dart';

import '../../application/discord_social_presence_controller.dart';

final class DiscordSocialPresenceScope
    extends InheritedNotifier<DiscordSocialPresenceController> {
  const DiscordSocialPresenceScope({
    required DiscordSocialPresenceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DiscordSocialPresenceController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DiscordSocialPresenceScope>()
          ?.notifier;
}
