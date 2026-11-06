import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// The few things full screen needs of the app's own window.
///
/// A seam in front of window_manager, so tests can stand in for it: in a
/// widget test the plugin's channel does not exist.
abstract interface class AppWindow {
  Future<bool> isFullScreen();
  Future<void> setFullScreen(bool fullScreen);
  Future<bool> isMaximized();
  Future<void> maximize();
  Future<Rect> getBounds();
  Future<void> setBounds(Rect bounds);
}

/// The desktop window, through window_manager.
final class WindowManagerAppWindow implements AppWindow {
  WindowManagerAppWindow();

  /// The plugin needs this once before any call. Asked for here and not in
  /// main: only Windows sets the plugin up at startup today, and the call is
  /// safe to repeat.
  late final Future<void> _ready = windowManager.ensureInitialized();

  @override
  Future<bool> isFullScreen() async {
    await _ready;
    return windowManager.isFullScreen();
  }

  @override
  Future<void> setFullScreen(bool fullScreen) async {
    await _ready;
    await windowManager.setFullScreen(fullScreen);
  }

  @override
  Future<bool> isMaximized() async {
    await _ready;
    return windowManager.isMaximized();
  }

  @override
  Future<void> maximize() async {
    await _ready;
    await windowManager.maximize();
  }

  @override
  Future<Rect> getBounds() async {
    await _ready;
    return windowManager.getBounds();
  }

  @override
  Future<void> setBounds(Rect bounds) async {
    await _ready;
    await windowManager.setBounds(bounds);
  }
}

/// Puts the window in full screen and gives it back its size and place
/// after.
///
/// The frame is remembered here rather than left to the platform: Windows
/// restores it itself but re-maximizes later with a posted message, and
/// Linux and macOS differ again. So leaving waits for the platform to finish
/// first, then a maximized window is maximized again and any other is put
/// back where it was. Calls run one after another, so a leave asked for while
/// entering does not overtake it.
final class WindowFullScreen {
  WindowFullScreen(this._window);

  final AppWindow _window;
  Future<void> _queue = Future<void>.value();

  /// The frame before this class entered full screen, or null when it did
  /// not (a window the user had put in full screen already is left alone).
  ({Rect bounds, bool maximized})? _before;

  Future<bool> isFullScreen() => _window.isFullScreen();

  Future<void> enter() => _then(() async {
    if (_before != null || await _window.isFullScreen()) return;
    _before = (
      bounds: await _window.getBounds(),
      maximized: await _window.isMaximized(),
    );
    await _window.setFullScreen(true);
  });

  Future<void> leave() => _then(() async {
    final before = _before;
    if (before == null) return;
    _before = null;
    await _window.setFullScreen(false);
    if (before.maximized) {
      await _window.maximize();
    } else {
      await _window.setBounds(before.bounds);
    }
  });

  /// Runs [step] after the steps before it. Its failure goes to its own
  /// caller and does not stop the steps after it.
  Future<void> _then(Future<void> Function() step) {
    final next = _queue.then((_) => step());
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }
}
