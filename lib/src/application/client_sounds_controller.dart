import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../domain/client_sounds.dart';
import '../domain/soundboard_playback.dart';

/// Plays the client's own sounds, and holds the switch that turns them off.
///
/// Discord's file plays once it is on this machine. Until then the sound's
/// bundled fallback plays, or nothing, and the miss starts the fetch. Loops
/// (the ring tones) have their own player, so a one-shot sound does not cut
/// a ring short.
final class ClientSoundsController extends ChangeNotifier
    implements ClientSoundPlayer {
  ClientSoundsController({
    required ClientSoundLibrary library,
    required ClientSoundSettingsRepository repository,
    required SoundboardAudioPlayer Function() playerFactory,

    /// Whether something else, such as streamer mode, holds sounds back.
    bool Function()? isSilenced,
  }) : _library = library,
       _repository = repository,
       _playerFactory = playerFactory,
       _isSilenced = isSilenced ?? _never;

  static bool _never() => false;

  final ClientSoundLibrary _library;
  final ClientSoundSettingsRepository _repository;
  final SoundboardAudioPlayer Function() _playerFactory;
  final bool Function() _isSilenced;

  SoundboardAudioPlayer? _cuePlayer;
  SoundboardAudioPlayer? _tonePlayer;
  ClientSound? _loop;

  /// Bumped by every loop change, so a loop whose file is still being looked
  /// up does not start after it was replaced or stopped.
  int _loopTurn = 0;
  bool _enabled = true;
  bool _loaded = false;

  /// Set once the person flips the switch. Their choice is newer than the
  /// saved one, so a read still on its way does not replace it.
  bool _switched = false;
  bool _disposed = false;

  bool get enabled => _enabled;

  bool get _audible => _enabled && !_isSilenced() && !_disposed;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final saved = await _repository.loadEnabled();
    if (_switched || _disposed) return;
    _enabled = saved;
    if (!_enabled) _silenceLoop();
    _notify();
  }

  Future<void> setEnabled({required bool enabled}) async {
    _switched = true;
    if (_enabled == enabled) return;
    _enabled = enabled;
    final loop = _loop;
    if (!enabled) {
      _silenceLoop();
    } else if (loop != null) {
      _startLoop(loop);
    }
    _notify();
    try {
      await _repository.saveEnabled(enabled: enabled);
    } on Object catch (error) {
      AppLog.warning('sounds', 'sound switch not saved', error: error);
    }
  }

  /// Fetches every sound that is not on this machine yet, in the background.
  void prefetch() => unawaited(_library.fetchAll());

  @override
  void play(ClientSound sound) {
    if (!_audible) return;
    unawaited(_start(_cuePlayer ??= _playerFactory(), sound));
  }

  @override
  void loop(ClientSound sound) {
    _loop = sound;
    _startLoop(sound);
  }

  @override
  void stopLoop() {
    if (_loop == null) return;
    _loop = null;
    _silenceLoop();
  }

  void _startLoop(ClientSound sound) {
    final turn = ++_loopTurn;
    if (!_audible) return;
    unawaited(_start(_tonePlayer ??= _playerFactory(), sound, loopTurn: turn));
  }

  void _silenceLoop() {
    _loopTurn++;
    final player = _tonePlayer;
    if (player != null) unawaited(_quietly(player.stop));
  }

  Future<void> _start(
    SoundboardAudioPlayer player,
    ClientSound sound, {
    int? loopTurn,
  }) => _quietly(() async {
    final url = await _library.localUrl(sound) ?? sound.fallbackAsset;
    if (url == null || _disposed) return;
    if (loopTurn != null && loopTurn != _loopTurn) return;
    await player.play(url, loop: loopTurn != null);
  });

  /// A sound is a courtesy: a machine that cannot play one is still worth
  /// using, so a failure is logged and nothing else.
  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      AppLog.warning('sounds', 'client sound would not play', error: error);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_cuePlayer?.dispose());
    unawaited(_tonePlayer?.dispose());
    super.dispose();
  }
}
