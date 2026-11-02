import 'package:flutter/widgets.dart';

import '../../application/self_video_controller.dart';

/// Publishes the account's own camera to the conversation pane, for the Room's
/// toolbar.
final class SelfVideoScope extends InheritedNotifier<SelfVideoController> {
  const SelfVideoScope({
    required SelfVideoController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], without subscribing the caller to it. The
  /// button listens on its own, so the pane does not rebuild with the camera.
  static SelfVideoController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SelfVideoScope>()!.notifier!;
}
