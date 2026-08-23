import 'package:flutter/widgets.dart';

import '../../domain/external_link_launcher.dart';

/// Publishes the external link launcher to the conversation pane.
///
/// A plain service rather than a listenable, so this is an [InheritedWidget].
final class ExternalLinkLauncherScope extends InheritedWidget {
  const ExternalLinkLauncherScope({
    required this.launcher,
    required super.child,
    super.key,
  });

  final ExternalLinkLauncher launcher;

  @override
  bool updateShouldNotify(ExternalLinkLauncherScope oldWidget) =>
      oldWidget.launcher != launcher;

  static ExternalLinkLauncher? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ExternalLinkLauncherScope>()
          ?.launcher;
}
