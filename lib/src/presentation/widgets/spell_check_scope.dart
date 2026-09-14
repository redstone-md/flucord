import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Publishes the local spell check service to the composer.
///
/// One instance for the whole app: the dictionary is read once and shared,
/// rather than every composer reading its own copy into memory. A plain
/// service rather than a listenable, so this is an [InheritedWidget].
final class SpellCheckScope extends InheritedWidget {
  const SpellCheckScope({
    required this.service,
    required super.child,
    super.key,
  });

  final SpellCheckService service;

  @override
  bool updateShouldNotify(SpellCheckScope oldWidget) =>
      oldWidget.service != service;

  static SpellCheckService? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SpellCheckScope>()?.service;
}
