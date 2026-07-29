import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/keybind.dart';
import '../platform/global_keyboard_hook.dart';

/// Runs one bound action. [pressed] is false on release, which is what tells a
/// hold action — push to talk — when to stop.
typedef KeybindHandler =
    void Function(KeybindAction action, {required bool pressed});

/// The keyboard shortcuts, and the recording of new ones.
///
/// Deliberately not Flutter's `Shortcuts` widget: these have to fire wherever
/// the focus happens to be, including while a message is being typed, and a
/// widget-scoped shortcut only fires for the subtree below it. The handler is
/// installed on the keyboard itself for the same reason Discord's is installed
/// on the window.
///
/// A binding fires from behind another window too, through the system-wide
/// hook. Where the hook cannot be installed — another platform, or a build
/// without the native module — the bindings still work while this window has
/// focus, and the settings page says which of the two is happening rather
/// than implying a global key that would quietly do nothing.
final class KeybindController extends ChangeNotifier {
  KeybindController({
    required KeybindRepository repository,
    required KeybindHandler onTriggered,
    GlobalKeyboardHook? hook,
  }) : _repository = repository,
       _onTriggered = onTriggered,
       _hook = hook ?? const UnavailableGlobalKeyboardHook();

  final KeybindRepository _repository;
  final KeybindHandler _onTriggered;
  final GlobalKeyboardHook _hook;
  StreamSubscription<GlobalKeyEvent>? _globalKeys;

  final Map<KeybindAction, Keybind> _bindings = {};
  final Set<KeybindAction> _held = {};

  /// Keys down right now, so a chord reported by both the hook and the focused
  /// keyboard runs its action once.
  final Set<int> _pressed = {};
  KeybindAction? _recording;
  bool _loaded = false;
  bool _disposed = false;

  Map<KeybindAction, Keybind> get bindings => Map.unmodifiable(_bindings);

  /// Which action is waiting for a chord, or `null`.
  KeybindAction? get recording => _recording;

  bool get isLoaded => _loaded;

  Keybind? bindingFor(KeybindAction action) => _bindings[action];

  /// Whether bindings reach the client from behind another window.
  bool get isGlobal => _hook.isRunning;

  /// Whether this build could install a system-wide hook at all.
  bool get supportsGlobal => _hook.isSupported;

  Future<void> load() async {
    if (_loaded) return;
    _bindings
      ..clear()
      ..addAll(await _repository.load());
    _loaded = true;
    // Started after the bindings are read: a key arriving before them would
    // match nothing and be dropped, which is harmless but pointless work.
    await _startHook();
    _notify();
  }

  Future<void> _startHook() async {
    if (!_hook.isSupported || _hook.isRunning) return;
    if (!await _hook.start()) return;
    _globalKeys = _hook.events.listen(_acceptGlobalKey);
  }

  /// A key seen anywhere on the machine.
  ///
  /// Fed through the same matching as a focused key, minus the swallowing:
  /// the hook reports and never consumes, so a global binding cannot take a
  /// keystroke away from whatever the user was typing into.
  void _acceptGlobalKey(GlobalKeyEvent event) {
    final keyId = event.key.keyId;
    final modifiers = _modifiersOfBits(event.modifiers);
    if (_recording != null) {
      // Recording reads the focused keyboard, which is where somebody setting
      // a binding is actually looking. Assigning from the hook as well would
      // record the chord twice.
      return;
    }
    if (event.isDown) {
      _onDown(keyId, modifiers);
      return;
    }
    _onUp(keyId);
  }

  static Set<KeybindModifier> _modifiersOfBits(int bits) => {
    if (bits & 1 != 0) KeybindModifier.control,
    if (bits & 2 != 0) KeybindModifier.shift,
    if (bits & 4 != 0) KeybindModifier.alt,
    if (bits & 8 != 0) KeybindModifier.meta,
  };

  /// Starts listening for the next chord, which will be assigned to [action].
  void record(KeybindAction action) {
    _recording = action;
    _notify();
  }

  void cancelRecording() {
    if (_recording == null) return;
    _recording = null;
    _notify();
  }

  Future<void> clear(KeybindAction action) async {
    if (_bindings.remove(action) == null) return;
    _held.remove(action);
    _notify();
    await _repository.save(_bindings);
  }

  /// Feeds one key event in, answering whether it was consumed.
  ///
  /// Consumed means the key does not reach whatever had focus: a bound chord
  /// must not also type its letter into the composer.
  /// Feeds one focused key event in, answering whether it was consumed.
  ///
  /// A chord that the hook already reported is still matched here so that it
  /// can be swallowed: the hook cannot stop the key reaching the composer, and
  /// only this can. The action does not run twice — [_onDown] refuses a hold
  /// that is already held, and a toggle is only run from whichever of the two
  /// arrives first.
  bool handleKeyEvent(KeyEvent event) {
    final modifiers = _modifiersOf(HardwareKeyboard.instance.logicalKeysPressed);
    final keyId = event.logicalKey.keyId;
    final recording = _recording;
    if (recording != null) {
      if (event is! KeyDownEvent) return true;
      // A modifier on its own is not a binding — it is somebody still building
      // one — so it is swallowed rather than assigned.
      if (_modifierOf(event.logicalKey) != null) return true;
      unawaited(_assign(recording, Keybind(keyId: keyId, modifiers: modifiers)));
      return true;
    }
    if (event is KeyDownEvent) return _onDown(keyId, modifiers);
    if (event is KeyUpEvent) return _onUp(keyId);
    // A repeat of a held key is swallowed for a bound chord so that holding
    // push-to-talk does not re-fire it dozens of times a second.
    return event is KeyRepeatEvent && _actionFor(keyId, modifiers) != null;
  }

  bool _onDown(int keyId, Set<KeybindModifier> modifiers) {
    final action = _actionFor(keyId, modifiers);
    if (action == null) return false;
    if (action.holdToUse) {
      if (!_held.add(action)) return true;
      _onTriggered(action, pressed: true);
      return true;
    }
    // A toggle arrives twice when the hook is running — once from the system
    // and once from the focused keyboard — and firing both would leave it
    // where it started.
    if (!_pressed.add(keyId)) return true;
    _onTriggered(action, pressed: true);
    return true;
  }

  /// Releasing a hold action ends it whatever the modifiers now are.
  ///
  /// Somebody who lets go of shift before the key would otherwise leave the
  /// microphone open: the release no longer matches the chord that opened it.
  bool _onUp(int keyId) {
    _pressed.remove(keyId);
    for (final action in _held.toList(growable: false)) {
      if (_bindings[action]?.keyId != keyId) continue;
      _held.remove(action);
      _onTriggered(action, pressed: false);
      return true;
    }
    return false;
  }

  KeybindAction? _actionFor(int keyId, Set<KeybindModifier> modifiers) {
    for (final entry in _bindings.entries) {
      if (entry.value.matches(keyId: keyId, modifiers: modifiers)) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> _assign(KeybindAction action, Keybind binding) async {
    // One chord, one action: leaving a duplicate would make which of the two
    // fires depend on map order.
    _bindings.removeWhere(
      (other, held) =>
          other != action &&
          held.matches(keyId: binding.keyId, modifiers: binding.modifiers),
    );
    _bindings[action] = binding;
    _recording = null;
    _notify();
    await _repository.save(_bindings);
  }

  static Set<KeybindModifier> _modifiersOf(Set<LogicalKeyboardKey> pressed) => {
    for (final key in pressed)
      if (_modifierOf(key) case final KeybindModifier modifier) modifier,
  };

  static KeybindModifier? _modifierOf(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.control) {
      return KeybindModifier.control;
    }
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.shift) {
      return KeybindModifier.shift;
    }
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.alt) {
      return KeybindModifier.alt;
    }
    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.meta) {
      return KeybindModifier.meta;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_globalKeys?.cancel());
    _globalKeys = null;
    unawaited(_hook.stop());
    super.dispose();
  }
}

/// How a chord reads in the settings list.
extension KeybindLabel on Keybind {
  String get label {
    const order = [
      KeybindModifier.control,
      KeybindModifier.alt,
      KeybindModifier.shift,
      KeybindModifier.meta,
    ];
    final parts = [
      for (final modifier in order)
        if (modifiers.contains(modifier)) _modifierLabels[modifier]!,
      LogicalKeyboardKey.findKeyByKeyId(keyId)?.keyLabel ?? 'Key $keyId',
    ];
    return parts.join(' + ');
  }

  static const _modifierLabels = {
    KeybindModifier.control: 'Ctrl',
    KeybindModifier.alt: 'Alt',
    KeybindModifier.shift: 'Shift',
    KeybindModifier.meta: 'Win',
  };
}
