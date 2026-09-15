import 'package:flutter/widgets.dart';

import '../../application/account_entitlements_controller.dart';

/// Publishes the entitlements plane to the settings window.
///
/// Same shape and same reason as the profile scope: the settings gear sits
/// in the rail, several layers from anything that knows about a session, and
/// a host with no Discord account installs no scope at all.
final class AccountEntitlementsScope
    extends InheritedNotifier<AccountEntitlementsController> {
  const AccountEntitlementsScope({
    required AccountEntitlementsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static AccountEntitlementsController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AccountEntitlementsScope>()
      ?.notifier;
}
