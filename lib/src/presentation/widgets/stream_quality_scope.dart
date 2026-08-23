import 'package:flutter/widgets.dart';

import '../../application/stream_quality_controller.dart';

/// Publishes stream quality to the settings window and anything else that
/// wants to say what a share or a camera will run at.
final class StreamQualityScope
    extends InheritedNotifier<StreamQualityController> {
  const StreamQualityScope({
    required StreamQualityController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static StreamQualityController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<StreamQualityScope>()
      ?.notifier;
}
