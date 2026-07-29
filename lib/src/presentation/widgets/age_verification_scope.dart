import 'package:flutter/widgets.dart';

import '../../application/age_verification_controller.dart';

/// Publishes age verification to the settings window.
///
/// Same shape and same reason as the profile scope: the settings gear sits in
/// the rail, several layers from anything that knows about a session, and a
/// host with no Discord account installs no scope at all.
final class AgeVerificationScope
    extends InheritedNotifier<AgeVerificationController> {
  const AgeVerificationScope({
    required AgeVerificationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static AgeVerificationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AgeVerificationScope>()
      ?.notifier;
}
