import 'package:flutter/widgets.dart';

import '../../application/room_focus.dart';

/// Hands the room's focus to the widgets that draw and change it.
final class RoomFocusScope extends InheritedNotifier<RoomFocus> {
  const RoomFocusScope({
    required RoomFocus focus,
    required super.child,
    super.key,
  }) : super(notifier: focus);

  /// The focus above [context], rebuilding the caller when it changes.
  static RoomFocus of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomFocusScope>()!.notifier!;

  /// The focus above [context], without subscribing: for imperative calls.
  static RoomFocus read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RoomFocusScope>()!.notifier!;
}
