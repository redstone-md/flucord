import 'package:flutter/widgets.dart';

import '../../application/remote_camera_controller.dart';

/// Publishes the remote cameras to the conversation pane.
///
/// The controller notifies per decoded picture, so depending on this scope is
/// also what keeps the camera tiles moving: every frame rebuilds whoever reads
/// the scope.
final class RemoteCameraScope extends InheritedNotifier<RemoteCameraController> {
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
