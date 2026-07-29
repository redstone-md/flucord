import 'package:flutter/widgets.dart';

import '../../application/streamer_mode_controller.dart';

/// Publishes streamer mode to everything that draws something worth hiding.
///
/// A scope rather than a parameter threaded through the tree: an invite link
/// can appear in a message, an embed, a reply preview or a search result, and
/// every one of those would otherwise need the controller passed to it — which
/// is exactly how one of them ends up forgotten and leaking on a stream.
final class StreamerModeScope
    extends InheritedNotifier<StreamerModeController> {
  const StreamerModeScope({
    required StreamerModeController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static StreamerModeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StreamerModeScope>()?.notifier;

  /// [text] with invite links replaced when the mode is on.
  static String redact(BuildContext context, String text) =>
      maybeOf(context)?.redact(text) ?? text;

  /// Whether personal details should be blanked where they are drawn.
  static bool hidesPersonalInformation(BuildContext context) =>
      maybeOf(context)?.hidesPersonalInformation ?? false;
}
