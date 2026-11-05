import 'package:flutter/widgets.dart';

import 'profile_card_route.dart';

/// Opens a person's profile card from any message text below it: the
/// timeline, search results, pinned messages, forwards and embeds alike.
class ProfileOpenerScope extends InheritedWidget {
  const ProfileOpenerScope({
    required this.open,
    required super.child,
    super.key,
  });

  final OpenProfileCard open;

  /// What opens a card from [context], or null with no scope above. The scope
  /// is read again at each tap, so a scope rebuilt since still answers.
  static OpenProfileCard? of(BuildContext context) {
    if (context.getInheritedWidgetOfExactType<ProfileOpenerScope>() == null) {
      return null;
    }
    return (userId, anchor) => context
        .getInheritedWidgetOfExactType<ProfileOpenerScope>()
        ?.open(userId, anchor);
  }

  @override
  bool updateShouldNotify(ProfileOpenerScope oldWidget) => false;
}
