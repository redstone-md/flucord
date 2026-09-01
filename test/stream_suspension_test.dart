import 'package:flucord/src/application/stream_suspension.dart';
import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/application/window_visible.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stream_room_harness.dart';

void main() {
  test('a window that leaves the screen suspends what is being watched', () {
    final visible = WindowVisible();
    final viewer = StreamViewerController(
      repositoryProvider: () => null,
      decoderFactory: StreamRoomDecoder.new,
    );
    final suspension = StreamSuspension(
      visible: visible,
      viewer: viewer,
    );
    addTearDown(suspension.dispose);
    addTearDown(viewer.dispose);

    // A window nothing has moved off the screen is on it.
    expect(visible.inView, isTrue);
    expect(viewer.isSuspended, isFalse);

    visible.setInView(false);
    expect(viewer.isSuspended, isTrue);

    visible.setInView(true);
    expect(viewer.isSuspended, isFalse);
  });

  test('a rule that is disposed stops following the window', () {
    final visible = WindowVisible();
    final viewer = StreamViewerController(
      repositoryProvider: () => null,
      decoderFactory: StreamRoomDecoder.new,
    );
    final suspension = StreamSuspension(
      visible: visible,
      viewer: viewer,
    );
    addTearDown(viewer.dispose);

    suspension.dispose();
    visible.setInView(false);

    // The viewer is going away, and a window event must not reach a
    // controller that has already stopped listening.
    expect(viewer.isSuspended, isFalse);
  });
}
