import 'dart:async';
import 'dart:ui';

import 'package:flucord/src/platform/window_full_screen.dart';

/// A window that records what was asked of it, in order, for tests that must
/// never reach window_manager's plugin channel.
final class FakeAppWindow implements AppWindow {
  FakeAppWindow({
    this.bounds = const Rect.fromLTWH(100, 80, 1280, 720),
    this.maximized = false,
  });

  Rect bounds;
  bool maximized;
  bool fullScreen = false;
  final List<String> calls = [];

  /// When set, leaving full screen waits on it, as a platform that is slow
  /// to give the frame back does.
  Completer<void>? leaveGate;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> setFullScreen(bool value) async {
    calls.add(value ? 'enter' : 'leave');
    if (!value) await leaveGate?.future;
    fullScreen = value;
    if (!value) calls.add('left');
  }

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> maximize() async {
    calls.add('maximize');
    maximized = true;
  }

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<void> setBounds(Rect value) async {
    calls.add('setBounds $value');
    bounds = value;
  }
}
