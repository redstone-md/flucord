import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/soundboard.dart';

/// Drives the soundboard picker for one voice channel.
final class SoundboardController extends ChangeNotifier {
  SoundboardController(this._repositoryProvider);

  final SoundboardRepository? Function() _repositoryProvider;

  SoundboardRepository? _repository;
  StreamSubscription<String>? _updates;
  bool _bound = false;
  bool _disposed = false;

  String? _guildId;
  bool _isLoading = false;
  bool _isSending = false;
  Object? _error;
  final Set<String> _loadedGuilds = {};

  bool get isSupported {
    _bind();
    return _repository != null;
  }

  String? get guildId => _guildId;

  List<SoundboardSound> get sounds => _guildId == null
      ? const []
      : _repository?.soundsFor(_guildId!) ?? const [];

  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  Object? get error => _error;

  /// Points the controller at a server, reading its sounds the first time.
  void show(String? guildId) {
    _bind();
    if (_guildId == guildId) return;
    _guildId = guildId;
    _error = null;
    _notify();
    if (guildId != null && !_loadedGuilds.contains(guildId)) unawaited(load());
  }

  Future<void> load() async {
    _bind();
    final repository = _repository;
    final guildId = _guildId;
    if (repository == null || guildId == null || _isLoading) return;
    _isLoading = true;
    _error = null;
    _notify();
    try {
      await repository.loadSounds(guildId);
      _loadedGuilds.add(guildId);
    } on Object catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Plays [sound] into [channelId].
  Future<bool> play(String channelId, SoundboardSound sound) async {
    final repository = _repository;
    // A sound the server lost its boost level for is shown but cannot be
    // played, so it is refused here rather than sent for a 403.
    if (repository == null || _isSending || !sound.isAvailable) return false;
    _isSending = true;
    _error = null;
    _notify();
    try {
      await repository.playSound(channelId, sound);
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _isSending = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_updates?.cancel());
    _repository = repository;
    _updates = repository?.updates.listen(_accept);
    // A new session has loaded nothing, whatever the last one had.
    _loadedGuilds.clear();
    return true;
  }

  void _accept(String guildId) {
    if (guildId == _guildId) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
