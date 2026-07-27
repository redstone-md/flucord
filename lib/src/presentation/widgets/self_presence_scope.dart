import 'package:flutter/widgets.dart';

import '../../application/self_presence_controller.dart';

/// Publishes the account's own presence to the chrome that renders it.
///
/// The account panel sits three layers under anything that knows about a
/// transport, and threading a presence service through the channel sidebar
/// would put it in the signature of a widget that has no interest in it.
/// Reading from a scope also means a status set on another device repaints the
/// panel without anybody rebuilding the tree by hand.
final class SelfPresenceScope
    extends InheritedNotifier<SelfPresenceController> {
  const SelfPresenceScope({
    required SelfPresenceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  ///
  /// Deliberately nullable: a transport with no presence plane installs none,
  /// and the widget tests that pump a single pane run without one.
  static SelfPresenceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelfPresenceScope>()?.notifier;
}
