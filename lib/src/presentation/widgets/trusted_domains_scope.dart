import 'package:flutter/widgets.dart';

import '../../application/trusted_domains_controller.dart';

/// Publishes the trusted hosts to every link in the app.
///
/// The app puts this above the navigator, so a link in a dialog asks too.
/// A link with no scope above it opens without asking.
final class TrustedDomainsScope extends InheritedWidget {
  const TrustedDomainsScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final TrustedDomainsController controller;

  @override
  bool updateShouldNotify(TrustedDomainsScope oldWidget) =>
      oldWidget.controller != controller;

  static TrustedDomainsController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TrustedDomainsScope>()?.controller;
}
