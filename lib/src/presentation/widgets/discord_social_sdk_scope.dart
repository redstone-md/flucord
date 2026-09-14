import 'package:flutter/widgets.dart';

import '../../application/discord_social_sdk_controller.dart';

final class DiscordSocialSdkScope
    extends InheritedNotifier<DiscordSocialSdkController> {
  const DiscordSocialSdkScope({
    required DiscordSocialSdkController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DiscordSocialSdkController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiscordSocialSdkScope>();
    assert(
      scope != null,
      'DiscordSocialSdkScope is missing above this widget.',
    );
    return scope!.notifier!;
  }
}
