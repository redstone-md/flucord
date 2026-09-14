import 'package:flutter/foundation.dart';

/// Whether this client's window can be seen on screen, and whether it has
/// the focus.
///
/// The two are different facts with different readers. A window is off
/// screen when nothing of it is left to look at: minimized, or hidden away to
/// the tray; watched sessions read that to suspend (ADR-0003), and a window
/// that merely lost the focus still draws them. The self-preview reads both:
/// a sender who is looking at their game, with this window behind it or
/// minimized, is not paying a decoder for a picture nobody sees.
///
/// Only the desktop chrome knows either, which is why the platform layer
/// calls [setInView] and [setFocused] rather than this class guessing.
///
/// Starts on screen and focused, which is where a window is before anything
/// has moved it off or taken the focus away.
final class WindowVisible extends ChangeNotifier {
  bool _inView = true;
  bool _focused = true;

  bool get inView => _inView;

  bool get focused => _focused;

  /// Whether the window is both on screen and focused: what the self-preview
  /// needs to be worth decoding.
  bool get isLookedAt => _inView && _focused;

  /// Told by the desktop seam whenever the window becomes visible or leaves
  /// the screen. A repeat of what is already true says nothing, because
  /// window events arrive in bursts and every one of them would otherwise be
  /// a rebuild.
  void setInView(bool value) {
    if (_inView == value) return;
    _inView = value;
    notifyListeners();
  }

  /// Told by the desktop seam whenever the window gains or loses the focus.
  void setFocused(bool value) {
    if (_focused == value) return;
    _focused = value;
    notifyListeners();
  }
}
