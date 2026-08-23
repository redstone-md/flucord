import 'package:flutter/widgets.dart';

import '../../application/stream_viewer_controller.dart';

/// Publishes the stream viewer to the conversation pane.
final class StreamViewerScope extends InheritedNotifier<StreamViewerController> {
  const StreamViewerScope({
    required StreamViewerController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static StreamViewerController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StreamViewerScope>()?.notifier;

  static StreamViewerController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'StreamViewerScope is missing above this widget.',
    );
    return controller!;
  }
  /// The controller above [context], without subscribing the caller to it:
  /// for imperative calls, and for widgets that listen on their own.
  static StreamViewerController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StreamViewerScope>()!.notifier!;

}
