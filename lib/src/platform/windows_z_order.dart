import 'dart:ffi';

/// The top-level windows on Windows, front first.
///
/// `GW_CHILD` from the desktop is the first top-level window, and
/// `GW_HWNDNEXT` walks the rest in z-order. The Stream picker lists windows
/// with it, and the capture shield finds this client's own window with it.
final class WindowsZOrder {
  WindowsZOrder(DynamicLibrary user32)
    : _getWindow = user32
          .lookupFunction<
            IntPtr Function(IntPtr, Uint32),
            int Function(int, int)
          >('GetWindow'),
      _getDesktopWindow = user32
          .lookupFunction<IntPtr Function(), int Function()>(
            'GetDesktopWindow',
          );

  static const _gwChild = 5;
  static const _gwHwndNext = 2;

  final int Function(int, int) _getWindow;
  final int Function() _getDesktopWindow;

  /// Each top-level window's handle, front first, hidden ones included.
  Iterable<int> get windows sync* {
    for (
      var window = _getWindow(_getDesktopWindow(), _gwChild);
      window != 0;
      window = _getWindow(window, _gwHwndNext)
    ) {
      yield window;
    }
  }
}
