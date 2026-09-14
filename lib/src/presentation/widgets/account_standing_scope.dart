import 'package:flutter/widgets.dart';

import '../../application/account_standing_controller.dart';

/// Publishes the account's safety record to the settings window.
///
/// Same shape and same reason as the profile scope: the settings gear sits in
/// the rail, several layers from anything that knows about a session, and a
/// host with no Discord account installs no scope at all.
final class AccountStandingScope
    extends InheritedNotifier<AccountStandingController> {
  const AccountStandingScope({
    required AccountStandingController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static AccountStandingController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AccountStandingScope>()
      ?.notifier;
}
