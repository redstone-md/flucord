import 'package:flutter/widgets.dart';

import '../../application/user_settings_controller.dart';
import '../../domain/user_settings.dart';

/// Publishes the account settings to the widgets that render for them.
///
/// Message rows sit several layers below anything that knows about a session,
/// and threading four display flags through every constructor between here and
/// there would put the settings in the signature of widgets that do not care
/// about them. Reading from the scope also means a dispatch from another
/// device repaints the timeline without anybody rebuilding the tree by hand.
final class UserSettingsScope
    extends InheritedNotifier<UserSettingsController> {
  const UserSettingsScope({
    required UserSettingsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller above [context], or `null` when there is no scope.
  ///
  /// Deliberately nullable rather than asserted: a settings surface is
  /// optional by design. Hosts with no Discord account, and the widget tests
  /// that pump a single pane, run without one.
  static UserSettingsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserSettingsScope>()?.notifier;

  /// The message display settings in force.
  ///
  /// Hosts that never install a scope — the widget tests for a single pane,
  /// and every transport with no Discord account behind it — get Flucord's
  /// defaults, which render everything.
  static MessageDisplayPreferences displayOf(BuildContext context) =>
      maybeOf(context)?.settings?.messageDisplay ??
      const MessageDisplayPreferences();

  static TimestampHourCycle hourCycleOf(BuildContext context) =>
      maybeOf(context)?.settings?.appearance.timestampHourCycle ??
      TimestampHourCycle.auto;
}
