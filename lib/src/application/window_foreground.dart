import 'package:flutter/foundation.dart';

/// Whether this client's window is in the foreground.
///
/// Only the desktop chrome knows: the window manager is what says another
/// application took the focus, which is not something Flutter's own lifecycle
/// reports on the desktop. Watched sessions read it to suspend, and nothing
/// on Discord's side follows it (ADR-0003).
///
/// Starts in the foreground, which is where a window is before anything has
/// taken the focus away from it.
final class WindowForeground extends ChangeNotifier {
  bool _inForeground = true;

  bool get inForeground => _inForeground;

  /// Told by the desktop seam whenever the window gains or loses the focus.
  /// A repeat of what is already true says nothing, because focus events
  /// arrive in bursts and every one of them would otherwise be a rebuild.
  void setInForeground(bool value) {
    if (_inForeground == value) return;
    _inForeground = value;
    notifyListeners();
  }
}
