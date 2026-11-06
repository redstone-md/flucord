import 'dart:async';
import 'dart:ui';

import 'package:flucord/src/platform/window_full_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_app_window.dart';

void main() {
  const before = Rect.fromLTWH(100, 80, 1280, 720);

  test('leaving gives the window back its size and place', () async {
    final window = FakeAppWindow(bounds: before);
    final fullScreen = WindowFullScreen(window);

    await fullScreen.enter();
    expect(await fullScreen.isFullScreen(), isTrue);
    // The platform hands back some other frame on its way out.
    window.bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
    await fullScreen.leave();

    expect(window.calls, ['enter', 'leave', 'left', 'setBounds $before']);
    expect(window.bounds, before);
    expect(await fullScreen.isFullScreen(), isFalse);
  });

  test('a maximized window is maximized again, not resized', () async {
    final window = FakeAppWindow(bounds: before, maximized: true);
    final fullScreen = WindowFullScreen(window);

    await fullScreen.enter();
    window.maximized = false;
    await fullScreen.leave();

    expect(window.calls, ['enter', 'leave', 'left', 'maximize']);
  });

  test('the restore waits for the platform to leave full screen', () async {
    final window = FakeAppWindow(bounds: before)..leaveGate = Completer();
    final fullScreen = WindowFullScreen(window);
    await fullScreen.enter();

    final leaving = fullScreen.leave();
    await pumpEventQueue();
    expect(window.calls, ['enter', 'leave']);

    window.leaveGate!.complete();
    await leaving;
    expect(window.calls.last, 'setBounds $before');
  });

  test('a leave asked for while entering runs after it', () async {
    final window = FakeAppWindow(bounds: before);
    final fullScreen = WindowFullScreen(window);

    unawaited(fullScreen.enter());
    await fullScreen.leave();

    expect(window.calls, ['enter', 'leave', 'left', 'setBounds $before']);
  });

  test('a window already full screen is left as it was', () async {
    final window = FakeAppWindow(bounds: before)..fullScreen = true;
    final fullScreen = WindowFullScreen(window);

    await fullScreen.enter();
    await fullScreen.leave();

    expect(window.calls, isEmpty);
    expect(window.fullScreen, isTrue);
  });

  test('a failed leave can be asked for again', () async {
    final window = FakeAppWindow(bounds: before);
    final fullScreen = WindowFullScreen(window);
    await fullScreen.enter();

    final gate = window.leaveGate = Completer<void>();
    final leaving = fullScreen.leave();
    gate.completeError(StateError('denied'));
    await expectLater(leaving, throwsStateError);
    window.leaveGate = null;
    window.bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
    await fullScreen.leave();

    expect(window.fullScreen, isFalse);
    expect(window.bounds, before);
  });
}
