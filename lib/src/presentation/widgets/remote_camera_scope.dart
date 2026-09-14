import 'package:flutter/widgets.dart';

import '../../application/remote_camera_controller.dart';

/// Publishes the remote cameras to the conversation pane.
///
/// The controller announces when a camera appears, not every picture it
/// decodes: the pictures travel on the per-sender streams the camera tiles
/// hold, so a camera runs at its frame rate without rebuilding the pane
/// around it.
final class RemoteCameraScope
    extends InheritedNotifier<RemoteCameraController> {
  const RemoteCameraScope({
    required RemoteCameraController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static RemoteCameraController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RemoteCameraScope>()?.notifier;

  static RemoteCameraController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'RemoteCameraScope is missing above this widget.',
    );
    return controller!;
  }
}
