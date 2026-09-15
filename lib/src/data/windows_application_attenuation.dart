import 'dart:ffi';
import 'dart:io';

import '../domain/voice_processing.dart';

/// An attenuation that does nothing, on a platform that has no way to reach
/// other applications' audio.
final class UnavailableApplicationAttenuation
    implements ApplicationAttenuation {
  const UnavailableApplicationAttenuation();

  @override
  bool get isSupported => false;

  @override
  Future<void> attenuate(double level) async {}

  @override
  Future<void> release() async {}

  @override
  Future<void> dispose() async {}
}

/// Other applications' volume through `flucord_audio.dll`.
///
/// One process at a time holds the endpoint's session list, so the calls are
/// plain exports rather than a handle: the attenuation this client owns is
/// the only one the module carries.
final class WindowsApplicationAttenuation implements ApplicationAttenuation {
  WindowsApplicationAttenuation()
    : this.withLibrary(Platform.isWindows ? _open() : null);

  /// The module handed in rather than opened, so a test can state that it
  /// is genuinely absent.
  WindowsApplicationAttenuation.withLibrary(this._library);

  static DynamicLibrary? _open() {
    try {
      return DynamicLibrary.open('flucord_audio.dll');
    } on Object {
      // A build without the native module still runs; attenuation simply
      // reports itself unavailable.
      return null;
    }
  }

  final DynamicLibrary? _library;
  double? _lastLevel;

  @override
  bool get isSupported => _library != null;

  @override
  Future<void> attenuate(double level) async {
    final library = _library;
    if (library == null) return;
    final held = level.clamp(0.0, 1.0);
    // Asked for the level already in force: the endpoint's sessions were
    // set to it and never released, and setting them again would re-read
    // the attenuated level as the remembered "before".
    if (_lastLevel == held) return;
    _lastLevel = held;
    library.lookupFunction<Int32 Function(Double), int Function(double)>(
      'flucord_audio_attenuate_others',
    )(held);
  }

  @override
  Future<void> release() async {
    final library = _library;
    if (library == null || _lastLevel == null) return;
    _lastLevel = null;
    library.lookupFunction<Int32 Function(), int Function()>(
      'flucord_audio_restore_others',
    )();
  }

  @override
  Future<void> dispose() async => release();
}
