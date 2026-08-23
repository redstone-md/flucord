import 'package:flutter/widgets.dart';

import '../../application/expression_favorites_controller.dart';

/// Publishes the starred expressions to the conversation pane.
final class ExpressionFavoritesScope
    extends InheritedNotifier<ExpressionFavoritesController> {
  const ExpressionFavoritesScope({
    required ExpressionFavoritesController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ExpressionFavoritesController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ExpressionFavoritesScope>()
          ?.notifier;

  static ExpressionFavoritesController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'ExpressionFavoritesScope is missing above this widget.',
    );
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static ExpressionFavoritesController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ExpressionFavoritesScope>()!.notifier!;

}
