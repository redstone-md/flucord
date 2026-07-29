import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

/// One key event seen anywhere on the machine.
final class GlobalKeyEvent {
  const GlobalKeyEvent({
    required this.key,
    required this.modifiers,
    required this.isDown,
  });

  final LogicalKeyboardKey key;

  /// The modifier bits the hook reported: 1 control, 2 shift, 4 alt, 8 meta.
  final int modifiers;

  final bool isDown;
}

/// Keys from outside this window.
///
/// The reason keybinds exist at all is push to talk, and push to talk that
/// only works while the client has focus is push to talk that does not work:
/// the whole point is holding a key while playing something else.
abstract interface class GlobalKeyboardHook {
  bool get isSupported;

  /// Whether the hook is installed right now.
  bool get isRunning;

  /// Every key the machine saw, until [stop].
  Stream<GlobalKeyEvent> get events;

  /// Installs the hook. Answers whether the system took it — a caller that
  /// assumed success would promise a global key that never fires.
  Future<bool> start();

  Future<void> stop();
}

/// A hook on a platform that has none. Never pretends to have installed one.
final class UnavailableGlobalKeyboardHook implements GlobalKeyboardHook {
  const UnavailableGlobalKeyboardHook();

  @override
  bool get isSupported => false;

  @override
  bool get isRunning => false;

  @override
  Stream<GlobalKeyEvent> get events => const Stream<GlobalKeyEvent>.empty();

  @override
  Future<bool> start() async => false;

  @override
  Future<void> stop() async {}
}

typedef _HookCallback =
    Void Function(Pointer<Void>, Int32, Int32, Int32);

/// `WH_KEYBOARD_LL` through `flucord_hotkeys.dll`.
final class WindowsGlobalKeyboardHook implements GlobalKeyboardHook {
  WindowsGlobalKeyboardHook()
    : this.withLibrary(Platform.isWindows ? _open() : null);

  /// The module handed in rather than opened.
  ///
  /// Null means it is genuinely absent, which is the case a test has to be
  /// able to state: passing null to the ordinary constructor would only mean
  /// "open it yourself", and on Windows it would.
  WindowsGlobalKeyboardHook.withLibrary(this._library);

  static DynamicLibrary? _open() {
    try {
      return DynamicLibrary.open('flucord_hotkeys.dll');
    } on Object {
      // A build without the native module still runs; global keys simply
      // report themselves unavailable.
      return null;
    }
  }

  final DynamicLibrary? _library;
  final StreamController<GlobalKeyEvent> _events =
      StreamController.broadcast();
  NativeCallable<_HookCallback>? _callback;
  bool _running = false;

  @override
  bool get isSupported => _library != null;

  @override
  bool get isRunning => _running;

  @override
  Stream<GlobalKeyEvent> get events => _events.stream;

  @override
  Future<bool> start() async {
    final library = _library;
    if (library == null || _running) return _running;
    final callback = NativeCallable<_HookCallback>.listener(_onKey);
    final status = library
        .lookupFunction<
          Int32 Function(Pointer<NativeFunction<_HookCallback>>, Pointer<Void>),
          int Function(Pointer<NativeFunction<_HookCallback>>, Pointer<Void>)
        >('flucord_hotkeys_start')(callback.nativeFunction, nullptr);
    if (status != 0) {
      callback.close();
      return false;
    }
    _callback = callback;
    _running = true;
    return true;
  }

  @override
  Future<void> stop() async {
    final library = _library;
    if (library == null || !_running) return;
    library.lookupFunction<Void Function(), void Function()>(
      'flucord_hotkeys_stop',
    )();
    _running = false;
    // Closed after the native stop returns: that call joins the hook thread,
    // so no further callback can be in flight by the time it does.
    _callback?.close();
    _callback = null;
  }

  void _onKey(
    Pointer<Void> userData,
    int virtualKey,
    int modifiers,
    int isDown,
  ) {
    final key = virtualKeyToLogicalKey(virtualKey);
    if (key == null || _events.isClosed) return;
    _events.add(
      GlobalKeyEvent(key: key, modifiers: modifiers, isDown: isDown != 0),
    );
  }

  Future<void> close() async {
    await stop();
    if (!_events.isClosed) await _events.close();
  }
}

/// A Windows virtual-key code as the logical key Flutter would have reported.
///
/// Only the keys somebody would bind to. A hook reports every key on the
/// machine, and mapping the ones nobody can bind would be inventing entries
/// for a table nothing reads — an unmapped code is dropped instead, which is
/// also what keeps a keystroke in another application from matching by
/// accident.
LogicalKeyboardKey? virtualKeyToLogicalKey(int virtualKey) {
  // 0x30-0x39 and 0x41-0x5a are the digits and letters, and Windows uses the
  // ASCII values for both — which is what Flutter's logical ids use as well.
  if ((virtualKey >= 0x30 && virtualKey <= 0x39) ||
      (virtualKey >= 0x41 && virtualKey <= 0x5a)) {
    return LogicalKeyboardKey(
      virtualKey >= 0x41 ? virtualKey + 0x20 : virtualKey,
    );
  }
  if (virtualKey >= 0x70 && virtualKey <= 0x87) {
    // F1 through F24, contiguous in both numberings.
    return LogicalKeyboardKey(
      LogicalKeyboardKey.f1.keyId + (virtualKey - 0x70),
    );
  }
  return _named[virtualKey];
}

const Map<int, LogicalKeyboardKey> _named = {
  0x08: LogicalKeyboardKey.backspace,
  0x09: LogicalKeyboardKey.tab,
  0x0d: LogicalKeyboardKey.enter,
  0x13: LogicalKeyboardKey.pause,
  0x14: LogicalKeyboardKey.capsLock,
  0x1b: LogicalKeyboardKey.escape,
  0x20: LogicalKeyboardKey.space,
  0x21: LogicalKeyboardKey.pageUp,
  0x22: LogicalKeyboardKey.pageDown,
  0x23: LogicalKeyboardKey.end,
  0x24: LogicalKeyboardKey.home,
  0x25: LogicalKeyboardKey.arrowLeft,
  0x26: LogicalKeyboardKey.arrowUp,
  0x27: LogicalKeyboardKey.arrowRight,
  0x28: LogicalKeyboardKey.arrowDown,
  0x2d: LogicalKeyboardKey.insert,
  0x2e: LogicalKeyboardKey.delete,
  0xa0: LogicalKeyboardKey.shiftLeft,
  0xa1: LogicalKeyboardKey.shiftRight,
  0xa2: LogicalKeyboardKey.controlLeft,
  0xa3: LogicalKeyboardKey.controlRight,
  0xa4: LogicalKeyboardKey.altLeft,
  0xa5: LogicalKeyboardKey.altRight,
  0x5b: LogicalKeyboardKey.metaLeft,
  0x5c: LogicalKeyboardKey.metaRight,
};
