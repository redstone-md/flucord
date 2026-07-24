import 'package:flutter/widgets.dart';

import '../../application/discord_friends_controller.dart';

final class DiscordFriendsScope
    extends InheritedNotifier<DiscordFriendsController> {
  const DiscordFriendsScope({
    required DiscordFriendsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DiscordFriendsController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiscordFriendsScope>();
    assert(scope != null, 'DiscordFriendsScope is missing above this widget.');
    return scope!.notifier!;
  }
}
