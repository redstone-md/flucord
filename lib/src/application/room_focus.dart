import 'package:flutter/foundation.dart';

/// Which participant's tile is on the stage, if any (CONTEXT.md: Focused).
///
/// Focus is a layout choice and nothing more: focusing a stream does not
/// start watching it, and stopping a watch does not move the focus. It is set
/// by the sender's own clicks, and by asking to watch, which is what a person
/// pressing "Watch" means to look at. It is cleared when its participant leaves
/// the room, and with the room.
final class RoomFocus extends ChangeNotifier {
  String? _userId;

  /// The participant whose tile is on the stage, or null for the grid.
  String? get userId => _userId;

  bool isFocused(String userId) => _userId == userId;

  void focus(String userId) => _set(userId);

  /// Focuses [userId], or returns to the grid when they already are.
  void toggle(String userId) => _set(_userId == userId ? null : userId);

  void clear() => _set(null);

  /// Keeps the focus on somebody who is still in the room.
  void keepAmong(Iterable<String> userIds) {
    final focused = _userId;
    if (focused != null && !userIds.contains(focused)) _set(null);
  }

  void _set(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    notifyListeners();
  }
}
