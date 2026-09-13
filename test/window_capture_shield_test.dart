import 'package:flucord/src/platform/window_capture_shield.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('which window the shield takes', () {
    test('the overlay in front does not win: the main window is picked', () {
      // The overlay is a top-most tool window, so while it is shown it is
      // this process's first visible window in z-order. Shielding it would
      // leave the main window on the recording with the shield reporting
      // success, which is the failure this pick exists for.
      const overlay = OwnWindowCandidate(
        className: 'FlucordOverlayWindow',
        isToolWindow: true,
      );
      const main = OwnWindowCandidate(
        className: WindowsWindowCaptureShield.mainWindowClass,
        isToolWindow: false,
      );

      expect(
        WindowsWindowCaptureShield.pickOwnWindow([overlay, main]),
        1,
      );
      // The same walk with the overlay hidden picks the main window either
      // way, so the two orders answer the same window.
      expect(
        WindowsWindowCaptureShield.pickOwnWindow([main, overlay]),
        0,
      );
    });

    test('a runner class that has moved on falls back to the first plain '
        'window', () {
      const overlay = OwnWindowCandidate(
        className: 'FlucordOverlayWindow',
        isToolWindow: true,
      );
      const other = OwnWindowCandidate(
        className: 'SomethingUnregistered',
        isToolWindow: false,
      );

      expect(
        WindowsWindowCaptureShield.pickOwnWindow([overlay, other]),
        1,
      );
    });

    test('a process of nothing but tool windows shields nothing', () {
      const overlay = OwnWindowCandidate(
        className: 'FlucordOverlayWindow',
        isToolWindow: true,
      );

      expect(WindowsWindowCaptureShield.pickOwnWindow([overlay]), -1);
      expect(WindowsWindowCaptureShield.pickOwnWindow(const []), -1);
    });
  });
}
