import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/user_settings.dart';
import '../domain/user_settings_repository.dart';

/// Holds the account settings the UI reads, and forwards the edits it makes.
///
/// The settings themselves are server state that can change without anybody
/// touching this window, so the controller never treats its own copy as
/// authoritative: it subscribes to the store and republishes whatever arrives,
/// including the value that comes back when a write is rejected.
final class UserSettingsController extends ChangeNotifier {
  UserSettingsController(this._repositoryProvider);

  final UserSettingsRepository? Function() _repositoryProvider;

  UserSettingsRepository? _repository;
  StreamSubscription<UserSettings>? _updates;
  UserSettings? _settings;
  Object? _loadError;
  bool _isLoading = false;
  bool _bound = false;
  bool _disposed = false;

  /// The settings as last known, or `null` before anything has arrived.
  UserSettings? get settings => _settings;

  /// Whether the connected transport can serve settings at all.
  ///
  /// A demo or bot session has no Discord account behind it, and the surface
  /// says so rather than showing controls that could never be saved.
  bool get isAvailable => _repository != null;

  bool get isLoading => _isLoading;

  /// Why the settings could not be read, or `null`.
  Object? get loadError => _loadError;

  /// Why the last save failed, or `null` when the last one went through.
  Object? get writeError => _repository?.lastWriteError;

  /// The theme Flucord should render for the stored appearance setting.
  ///
  /// `null` means the account expresses no preference Flucord can honour —
  /// either nothing is stored, or the stored theme is one of Discord's
  /// palettes Flucord does not ship — and the app keeps the theme it is
  /// already showing rather than guessing at a match.
  ThemeMode? get themeMode => switch (_settings?.appearance.theme) {
    UserSettingsTheme.light => ThemeMode.light,
    UserSettingsTheme.dark => ThemeMode.dark,
    _ => null,
  };

  /// Attaches to the active transport, loading its settings when it changes.
  void reconcile() {
    if (_bind()) unawaited(load());
  }

  /// Reads the settings, unless the gateway already delivered them.
  Future<void> load() async {
    _bind();
    final repository = _repository;
    if (repository == null || _disposed) return;
    if (repository.isLoaded) {
      _settings = repository.current;
      _loadError = null;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      _settings = await repository.load();
      _loadError = null;
    } on Object catch (error) {
      _loadError = error;
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Applies [patch] to the account.
  ///
  /// Returns `false` when there is no transport to save to, so a caller can
  /// keep the control where it was instead of showing a change that went
  /// nowhere.
  Future<bool> apply(UserSettingsPatch patch) async {
    final repository = _repository;
    if (repository == null || !repository.isLoaded || patch.isEmpty) {
      return false;
    }
    await repository.apply(patch);
    return true;
  }

  /// Sends any coalesced save immediately.
  Future<void> flush() async {
    await _repository?.flush();
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_updates?.cancel());
    _repository = repository;
    _settings = repository?.current;
    _loadError = null;
    _updates = repository?.updates.listen(_accept);
    return true;
  }

  void _accept(UserSettings settings) {
    if (_disposed) return;
    _settings = settings;
    _loadError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }
}
