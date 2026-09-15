import 'package:flutter/widgets.dart';

import '../../application/app_authorisation_controller.dart';

/// Publishes the app authorisation plane to the settings window.
///
/// Same shape and same reason as the profile scope: the settings gear sits
/// in the rail, several layers from anything that knows about a session, and
/// a host with no Discord account installs no scope at all.
final class AppAuthorisationScope
    extends InheritedNotifier<AppAuthorisationController> {
  const AppAuthorisationScope({
    required AppAuthorisationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static AppAuthorisationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppAuthorisationScope>()
      ?.notifier;
}
