import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Keeps this client's window out of screen recordings.
///
/// Streamer mode's one switch that is not a matter of what the client draws:
/// everything else hides information inside the window, and this hides the
/// window itself from whatever is capturing the desktop.
abstract interface class WindowCaptureShield {
  /// Whether this platform can do it at all.
  bool get isSupported;

  /// Excludes the window from capture, or puts it back. Answers whether the
  /// platform took the request — a caller that assumed success would tell
  /// somebody their window is hidden when it is still on the recording.
  bool setExcluded({required bool excluded});
}

/// A shield on a platform that has none. Always answers no, never pretends.
final class UnavailableWindowCaptureShield implements WindowCaptureShield {
  const UnavailableWindowCaptureShield();

  @override
  bool get isSupported => false;

  @override
  bool setExcluded({required bool excluded}) => false;
}

/// `SetWindowDisplayAffinity` on the client's own top-level window.
///
/// Straight FFI against `user32.dll` rather than a package: three calls, all
/// of them in the Windows API since Vista, and a dependency added for that
/// would be more to keep current than to write.
final class WindowsWindowCaptureShield implements WindowCaptureShield {
  WindowsWindowCaptureShield()
    : this.withLibraries(
        user32: Platform.isWindows ? _open('user32.dll') : null,
        kernel32: Platform.isWindows ? _open('kernel32.dll') : null,
      );

  /// The libraries handed in rather than opened.
  ///
  /// Null means the library is genuinely absent, which is the case a test has
  /// to be able to state: passing null to the ordinary constructor would only
  /// mean "open it yourself", and on Windows it would.
  const WindowsWindowCaptureShield.withLibraries({
    required DynamicLibrary? user32,
    required DynamicLibrary? kernel32,
  }) : _user32 = user32,
       _kernel32 = kernel32;

  /// Excluded from capture entirely: the recording sees whatever is behind the
  /// window. `WDA_MONITOR` — the older value — blanks it to black instead,
  /// which still tells a viewer exactly where the client is.
  static const int excludeFromCapture = 0x00000011;
  static const int none = 0x00000000;

  static DynamicLibrary? _open(String name) {
    try {
      return DynamicLibrary.open(name);
    } on Object {
      return null;
    }
  }

  final DynamicLibrary? _user32;
  final DynamicLibrary? _kernel32;

  @override
  bool get isSupported => _user32 != null && _kernel32 != null;

  @override
  bool setExcluded({required bool excluded}) {
    final user32 = _user32;
    if (user32 == null || _kernel32 == null) return false;
    final window = _findOwnWindow();
    if (window == nullptr) return false;
    final setAffinity = user32
        .lookupFunction<
          Int32 Function(Pointer<Void>, Uint32),
          int Function(Pointer<Void>, int)
        >('SetWindowDisplayAffinity');
    return setAffinity(window, excluded ? excludeFromCapture : none) != 0;
  }

  /// This process's first visible top-level window.
  ///
  /// Found by walking the windows rather than by title: the title follows the
  /// open channel, and matching on it would stop working the moment somebody
  /// switched servers.
  Pointer<Void> _findOwnWindow() {
    final user32 = _user32!;
    final kernel32 = _kernel32!;
    final currentProcessId = kernel32
        .lookupFunction<Uint32 Function(), int Function()>(
          'GetCurrentProcessId',
        )();
    final getWindow = user32
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Uint32),
          Pointer<Void> Function(Pointer<Void>, int)
        >('GetWindow');
    final getDesktopWindow = user32
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetDesktopWindow',
        );
    final isVisible = user32
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('IsWindowVisible');
    final threadProcess = user32
        .lookupFunction<
          Uint32 Function(Pointer<Void>, Pointer<Uint32>),
          int Function(Pointer<Void>, Pointer<Uint32>)
        >('GetWindowThreadProcessId');

    // GW_CHILD from the desktop is the first top-level window; GW_HWNDNEXT
    // walks the rest in z-order.
    var window = getWindow(getDesktopWindow(), 5);
    final owner = calloc<Uint32>();
    try {
      while (window != nullptr) {
        owner.value = 0;
        threadProcess(window, owner);
        if (owner.value == currentProcessId && isVisible(window) != 0) {
          return window;
        }
        window = getWindow(window, 2);
      }
    } finally {
      calloc.free(owner);
    }
    return nullptr;
  }
}
