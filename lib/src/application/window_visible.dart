import 'package:flutter/foundation.dart';

/// Whether this client's window can be seen on screen.
///
/// A window loses that not when another window takes the focus, but when
/// nothing of it is left to look at: minimized, or hidden away to the tray.
/// Only the desktop chrome knows, which is why the platform layer calls
/// [setInView] rather than this class guessing. Watched sessions read it to
/// suspend, and nothing on Discord's side follows it (ADR-0003).
///
/// Starts on screen, which is where a window is before anything has moved it
/// off.
final class WindowVisible extends ChangeNotifier {
  bool _inView = true;

  bool get inView => _inView;

  /// Told by the desktop seam whenever the window becomes visible or leaves
  /// the screen. A repeat of what is already true says nothing, because
  /// window events arrive in bursts and every one of them would otherwise be
  /// a rebuild.
  void setInView(bool value) {
    if (_inView == value) return;
    _inView = value;
    notifyListeners();
  }
}
