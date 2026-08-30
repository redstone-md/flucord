import 'package:flucord/src/application/stream_suspension.dart';
import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/application/window_foreground.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stream_room_harness.dart';

void main() {
  test('the window leaving the foreground suspends what is being watched', () {
    final foreground = WindowForeground();
    final viewer = StreamViewerController(
      repositoryProvider: () => null,
      decoderFactory: StreamRoomDecoder.new,
    );
    final suspension = StreamSuspension(
      foreground: foreground,
      viewer: viewer,
    );
    addTearDown(suspension.dispose);
    addTearDown(viewer.dispose);

    // A window nobody has taken the focus from is in the foreground.
    expect(foreground.inForeground, isTrue);
    expect(viewer.isSuspended, isFalse);

    foreground.setInForeground(false);
    expect(viewer.isSuspended, isTrue);

    foreground.setInForeground(true);
    expect(viewer.isSuspended, isFalse);
  });

  test('a rule that is disposed stops following the window', () {
    final foreground = WindowForeground();
    final viewer = StreamViewerController(
      repositoryProvider: () => null,
      decoderFactory: StreamRoomDecoder.new,
    );
    final suspension = StreamSuspension(
      foreground: foreground,
      viewer: viewer,
    );
    addTearDown(viewer.dispose);

    suspension.dispose();
    foreground.setInForeground(false);

    // The viewer is going away, and a window event must not reach a
    // controller that has already stopped listening.
    expect(viewer.isSuspended, isFalse);
  });
}
