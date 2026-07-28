import 'package:flutter/widgets.dart';

import '../../application/family_centre_controller.dart';

/// Publishes the family centre to the settings window.
///
/// Same shape and same reason as the profile scope: the settings gear sits in
/// the rail, several layers from anything that knows about a session, and a
/// host with no Discord account installs no scope at all.
final class FamilyCentreScope
    extends InheritedNotifier<FamilyCentreController> {
  const FamilyCentreScope({
    required FamilyCentreController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  static FamilyCentreController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FamilyCentreScope>()?.notifier;
}
