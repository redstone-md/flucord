import 'package:flutter/widgets.dart';

import '../../application/multi_factor_auth_controller.dart';

/// Publishes two-factor authentication to the settings window.
///
/// Same shape and same reason as the profile scope: the settings gear sits in
/// the rail, several layers from anything that knows about a session, and a
/// host with no Discord account installs no scope at all.
final class MultiFactorAuthScope
    extends InheritedNotifier<MultiFactorAuthController> {
  const MultiFactorAuthScope({
    required MultiFactorAuthController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static MultiFactorAuthController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MultiFactorAuthScope>()
      ?.notifier;
}
