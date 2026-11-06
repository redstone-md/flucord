import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:window_manager/window_manager.dart';

/// Asks for the user's attention through the window's taskbar button.
abstract interface class WindowAttention {
  /// Flashes the taskbar button until the window comes to the front.
  Future<void> request();

  /// Stops the flashing, if it is still going.
  Future<void> cancel();
}

/// A platform with no taskbar flash. Asking does nothing.
final class UnavailableWindowAttention implements WindowAttention {
  const UnavailableWindowAttention();

  @override
  Future<void> request() async {}

  @override
  Future<void> cancel() async {}
}

/// `FLASHWINFO`, the argument `FlashWindowEx` takes.
final class _FlashWindowInfo extends Struct {
  @Uint32()
  external int size;

  external Pointer<Void> window;

  @Uint32()
  external int flags;

  @Uint32()
  external int count;

  @Uint32()
  external int timeout;
}

/// `FlashWindowEx` on the main window, straight FFI against `user32.dll`, as
/// the capture shield does. window_manager has no flash, but it hands out the
/// main window's handle.
final class WindowsWindowAttention implements WindowAttention {
  WindowsWindowAttention({Future<int> Function()? windowHandle})
    : _windowHandle = windowHandle ?? windowManager.getId,
      _user32 = Platform.isWindows ? DynamicLibrary.open('user32.dll') : null;

  /// `FLASHW_TRAY | FLASHW_TIMERNOFG`: the taskbar button flashes until the
  /// window comes to the front.
  static const int _flashUntilForeground = 0x02 | 0x0C;

  /// `FLASHW_STOP`.
  static const int _stop = 0x00;

  final Future<int> Function() _windowHandle;
  final DynamicLibrary? _user32;

  @override
  Future<void> request() => _flash(_flashUntilForeground);

  @override
  Future<void> cancel() => _flash(_stop);

  Future<void> _flash(int flags) async {
    final user32 = _user32;
    if (user32 == null) return;
    final window = Pointer<Void>.fromAddress(await _windowHandle());
    final flashWindow = user32
        .lookupFunction<
          Int32 Function(Pointer<_FlashWindowInfo>),
          int Function(Pointer<_FlashWindowInfo>)
        >('FlashWindowEx');
    final info = calloc<_FlashWindowInfo>();
    try {
      info.ref
        ..size = sizeOf<_FlashWindowInfo>()
        ..window = window
        ..flags = flags
        ..count = 0
        ..timeout = 0;
      // The answer is whether the window was active before, not whether the
      // call worked, so there is nothing to read from it.
      flashWindow(info);
    } finally {
      calloc.free(info);
    }
  }
}
