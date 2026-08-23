import 'package:flutter/widgets.dart';

import '../../application/gif_picker_controller.dart';

/// Publishes the GIF picker to the conversation pane's composer.
final class GifPickerScope extends InheritedNotifier<GifPickerController> {
  const GifPickerScope({
    required GifPickerController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static GifPickerController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GifPickerScope>()?.notifier;

  static GifPickerController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'GifPickerScope is missing above this widget.');
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static GifPickerController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GifPickerScope>()!.notifier!;

}
