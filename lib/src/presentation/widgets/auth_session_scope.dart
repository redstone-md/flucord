import 'package:flutter/widgets.dart';

import '../../application/auth_session_controller.dart';

/// Publishes the account's sessions to the settings window.
///
/// Same shape and same reason as the profile scope: the settings gear sits in
/// the rail, several layers from anything that knows about a session, and a
/// host with no Discord account installs no scope at all.
final class AuthSessionScope extends InheritedNotifier<AuthSessionController> {
  const AuthSessionScope({
    required AuthSessionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static AuthSessionController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthSessionScope>()?.notifier;
}
