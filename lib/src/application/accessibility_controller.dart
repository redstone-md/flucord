import 'package:flutter/foundation.dart';

import '../domain/accessibility.dart';

/// The interface adjustments, applied as they are changed.
///
/// Each dial is applied first and saved after, so the interface answers the
/// drag rather than the disk. A write that fails leaves the new value on
/// screen and the failure where the settings window can show it.
final class AccessibilityController extends ChangeNotifier {
  AccessibilityController(this._repository);

  final AccessibilityRepository _repository;

  AccessibilitySettings _settings = AccessibilitySettings.off;
  bool _loaded = false;
  Object? _writeError;
  bool _disposed = false;

  AccessibilitySettings get settings => _settings;
  bool get isLoaded => _loaded;

  /// The last failed write, cleared by the next successful one.
  Object? get writeError => _writeError;

  /// The font scale in force, clamped to its usable range.
  double get fontScale => _settings.scaledFont;

  /// The zoom in force, clamped to its usable range.
  double get zoom => _settings.scaledZoom;

  /// Whether animations hold their end state rather than play.
  bool get reducesMotion => _settings.reducedMotion;

  /// Whether the composer underlines unknown words.
  bool get spellchecks => _settings.spellcheck;

  Future<void> load() async {
    if (_loaded) return;
    _settings = await _repository.load();
    _loaded = true;
    _notify();
  }

  Future<void> setFontScale(double value) =>
      _persist(_settings.copyWith(fontScale: value));

  Future<void> setZoom(double value) =>
      _persist(_settings.copyWith(zoom: value));

  Future<void> setReducedMotion({required bool reduced}) =>
      _persist(_settings.copyWith(reducedMotion: reduced));

  Future<void> setSpellcheck({required bool enabled}) =>
      _persist(_settings.copyWith(spellcheck: enabled));

  Future<void> _persist(AccessibilitySettings settings) async {
    _settings = settings;
    _notify();
    try {
      await _repository.save(_settings);
      _writeError = null;
    } catch (error) {
      _writeError = error;
    }
    _notify();
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
