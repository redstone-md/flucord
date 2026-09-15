import 'package:flutter/widgets.dart';

import '../../application/account_data_package_controller.dart';

/// Publishes the data-package controller to the settings window.
///
/// Same shape and same reason as the other account scopes: the settings gear
/// sits in the rail, several layers from anything that knows about a session,
/// and a host with no Discord account installs no scope at all.
final class AccountDataPackageScope
    extends InheritedNotifier<AccountDataPackageController> {
  const AccountDataPackageScope({
    required AccountDataPackageController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static AccountDataPackageController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AccountDataPackageScope>()
      ?.notifier;
}
