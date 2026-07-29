/// What a keybind can be set to do.
///
/// The names are Discord's own, taken from the desktop bundle rather than
/// invented, so a binding read here means the same thing it does there. Only
/// the actions Flucord can actually carry out are listed: the bundle also has
/// overlay, streamer-mode, clip and screenshot actions, and offering a binding
/// that silently did nothing would be worse than not offering one.
enum KeybindAction {
  pushToTalk('PUSH_TO_TALK', 'Push to talk', holdToUse: true),
  pushToMute('PUSH_TO_MUTE', 'Push to mute', holdToUse: true),
  toggleMute('TOGGLE_MUTE', 'Toggle mute'),
  toggleDeafen('TOGGLE_DEAFEN', 'Toggle deafen'),
  toggleCamera('TOGGLE_CAMERA', 'Toggle camera'),
  disconnectFromVoiceChannel(
    'DISCONNECT_FROM_VOICE_CHANNEL',
    'Disconnect from voice',
  ),
  toggleVoiceChannelChat(
    'TOGGLE_VOICE_CHANNEL_CHAT',
    'Toggle voice channel chat',
  ),
  toggleStreamerMode('TOGGLE_STREAMER_MODE', 'Toggle streamer mode');

  const KeybindAction(this.code, this.label, {this.holdToUse = false});

  /// The string the desktop client stores, so a binding is recognisable to
  /// anybody comparing the two.
  final String code;

  final String label;

  /// Whether the action runs while the keys are held rather than on the press.
  /// Push to talk is the reason this distinction exists.
  final bool holdToUse;

  static KeybindAction? fromCode(String code) {
    for (final action in values) {
      if (action.code == code) return action;
    }
    return null;
  }
}

/// One key combination.
///
/// Modifiers are held as a set rather than as flags because the order they
/// were pressed in is not part of the binding: control-shift-M and
/// shift-control-M are the same chord, and storing them differently would let
/// one shadow the other.
final class Keybind {
  Keybind({required this.keyId, Set<KeybindModifier> modifiers = const {}})
    : modifiers = Set.unmodifiable(modifiers);

  /// The logical key, as its integer id. Kept as a number rather than a name
  /// so a layout that reports an unnamed key still round-trips.
  final int keyId;

  final Set<KeybindModifier> modifiers;

  /// Whether this combination is the same chord as [other].
  bool matches({required int keyId, required Set<KeybindModifier> modifiers}) =>
      this.keyId == keyId &&
      this.modifiers.length == modifiers.length &&
      this.modifiers.containsAll(modifiers);

  Map<String, Object?> toJson() => {
    'key': keyId,
    'modifiers': [for (final modifier in modifiers) modifier.name],
  };

  /// Reads a stored binding, or `null` when the entry is not one.
  ///
  /// A file written by a newer build, or edited by hand, must not stop the
  /// client from starting: an unreadable binding is simply absent.
  static Keybind? fromJson(Object? value) {
    if (value is! Map) return null;
    final keyId = value['key'];
    if (keyId is! int) return null;
    final modifiers = value['modifiers'];
    return Keybind(
      keyId: keyId,
      modifiers: {
        if (modifiers is List)
          for (final name in modifiers)
            if (KeybindModifier.byName(name) case final KeybindModifier held)
              held,
      },
    );
  }
}

/// The modifiers a chord can carry, side-insensitive.
///
/// Discord treats the left and right of a pair as the same modifier, and a
/// binding that distinguished them would fail for anybody who happened to
/// press the other one.
enum KeybindModifier {
  control,
  shift,
  alt,
  meta;

  static KeybindModifier? byName(Object? name) {
    for (final modifier in values) {
      if (modifier.name == name) return modifier;
    }
    return null;
  }
}

/// Where the bindings are kept.
///
/// Local rather than on the account: `PreloadedUserSettings` has no keybind
/// group at all — the desktop client stores them on the machine — so putting
/// them in the settings blob would invent a shape Discord does not have.
abstract interface class KeybindRepository {
  Future<Map<KeybindAction, Keybind>> load();
  Future<void> save(Map<KeybindAction, Keybind> bindings);
}
