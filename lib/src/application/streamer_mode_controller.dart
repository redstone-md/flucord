import 'package:flutter/foundation.dart';

import '../domain/streamer_mode.dart';

/// Streamer mode: what the client hides while somebody is broadcasting it.
///
/// The switches persist and the mode itself does not. A client that came back
/// up still hiding everything would leave somebody hunting for what broke,
/// and the mode is about what is on screen right now rather than a preference.
final class StreamerModeController extends ChangeNotifier {
  StreamerModeController(this._repository);

  final StreamerModeRepository _repository;

  StreamerModeSettings _settings = StreamerModeSettings.off;
  bool _loaded = false;
  bool _wasAutomatic = false;
  bool _disposed = false;

  StreamerModeSettings get settings => _settings;

  bool get isEnabled => _settings.enabled;
  bool get isLoaded => _loaded;

  /// Whether personal details should be blanked wherever they are drawn.
  bool get hidesPersonalInformation => _settings.hidesPersonalInformation;

  bool get hidesInviteLinks => _settings.hidesInviteLinks;
  bool get silencesSounds => _settings.silencesSounds;
  bool get silencesNotifications => _settings.silencesNotifications;

  Future<void> load() async {
    if (_loaded) return;
    _settings = await _repository.load();
    _loaded = true;
    _notify();
  }

  Future<void> setEnabled({required bool enabled}) async {
    if (_settings.enabled == enabled) return;
    // Turning it on by hand clears the automatic flag's claim on it, so that
    // ending a stream does not switch off a mode somebody set deliberately.
    _wasAutomatic = false;
    _apply(_settings.copyWith(enabled: enabled));
  }

  Future<void> toggle() => setEnabled(enabled: !_settings.enabled);

  /// Follows whether this client is streaming.
  ///
  /// Only what it turned on does it turn off again: somebody who switched the
  /// mode on before going live keeps it after the stream ends.
  void reconcileStreaming({required bool isStreaming}) {
    if (!_settings.automatic) return;
    if (isStreaming && !_settings.enabled) {
      _wasAutomatic = true;
      _apply(_settings.copyWith(enabled: true));
      return;
    }
    if (!isStreaming && _settings.enabled && _wasAutomatic) {
      _wasAutomatic = false;
      _apply(_settings.copyWith(enabled: false));
    }
  }

  Future<void> setAutomatic({required bool automatic}) =>
      _persist(_settings.copyWith(automatic: automatic));

  Future<void> setHidePersonalInformation({required bool hide}) =>
      _persist(_settings.copyWith(hidePersonalInformation: hide));

  Future<void> setHideInviteLinks({required bool hide}) =>
      _persist(_settings.copyWith(hideInviteLinks: hide));

  Future<void> setDisableSounds({required bool disable}) =>
      _persist(_settings.copyWith(disableSounds: disable));

  Future<void> setDisableNotifications({required bool disable}) =>
      _persist(_settings.copyWith(disableNotifications: disable));

  /// Hides invite links in [text] when the mode is on, and leaves it alone
  /// otherwise.
  String redact(String text) =>
      _settings.hidesInviteLinks ? hideInviteLinks(text) : text;

  void _apply(StreamerModeSettings settings) {
    _settings = settings;
    _notify();
  }

  Future<void> _persist(StreamerModeSettings settings) async {
    _apply(settings);
    // Written without the live flag: only the switches outlive the session.
    await _repository.save(settings);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
