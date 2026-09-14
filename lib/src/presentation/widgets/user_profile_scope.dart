import 'package:flutter/widgets.dart';

import '../../application/user_profile_controller.dart';

/// Publishes the account's own profile controller to the chrome.
///
/// Kept separate from `UserSettingsScope` because the two answer to different
/// stores: settings arrive over settings-proto and are saved as you type, the
/// profile is a REST route committed once. Folding them together would put a
/// second nullable controller in the signature of every host that only wants
/// message display flags.
final class UserProfileScope extends InheritedNotifier<UserProfileController> {
  const UserProfileScope({
    required UserProfileController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static UserProfileController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserProfileScope>()?.notifier;
}
