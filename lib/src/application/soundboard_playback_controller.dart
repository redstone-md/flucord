import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/soundboard.dart';
import '../domain/soundboard_playback.dart';

/// Plays the sounds other people send into the voice channel this client is in.
///
/// Only that channel: Discord announces effects for every channel the session
/// can see, and playing all of them would have a room the user is not in make
/// noise. What counts as "here" is asked for at the moment an effect lands
/// rather than held, because the voice connection moves without telling this.
final class SoundboardPlaybackController extends ChangeNotifier {
  SoundboardPlaybackController({
    required SoundboardRepository? Function() repositoryProvider,
    required String? Function() connectedChannelId,
    required SoundboardAudioPlayer player,
  }) : _repositoryProvider = repositoryProvider,
       _connectedChannelId = connectedChannelId,
       _player = player;

  final SoundboardRepository? Function() _repositoryProvider;
  final String? Function() _connectedChannelId;
  final SoundboardAudioPlayer _player;

  SoundboardRepository? _repository;
  StreamSubscription<SoundboardPlayback>? _effects;
  bool _bound = false;
  bool _disposed = false;

  SoundboardPlayback? _lastPlayed;
  Object? _error;

  /// The effect most recently played through the speakers, or `null`.
  SoundboardPlayback? get lastPlayed => _lastPlayed;

  /// Why the last sound could not be played, or `null`.
  Object? get error => _error;

  /// Attaches to the active transport. Safe to call repeatedly.
  void reconcile() => _bind();

  @override
  void dispose() {
    _disposed = true;
    unawaited(_effects?.cancel());
    _effects = null;
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _accept(SoundboardPlayback playback) async {
    if (playback.channelId != _connectedChannelId()) return;
    final sound = _soundFor(playback);
    // A sound this session has never listed cannot be resolved to a url. The
    // effect is still recorded so the room can show who played something.
    _lastPlayed = playback;
    _error = null;
    _notify();
    if (sound == null) return;
    try {
      await _player.play(sound.url, volume: sound.volume);
    } on Object catch (error) {
      _error = error;
      _notify();
    }
  }

  /// Finds the sound in whichever server's catalogue holds it.
  ///
  /// A default sound has no guild, so the effect names none and the lookup
  /// falls back to the channel's own server, which is where the catalogue was
  /// loaded under.
  SoundboardSound? _soundFor(SoundboardPlayback playback) {
    final repository = _repository;
    if (repository == null) return null;
    final guildId = playback.guildId;
    if (guildId == null) return null;
    for (final sound in repository.soundsFor(guildId)) {
      if (sound.id == playback.soundId) return sound;
    }
    return null;
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_effects?.cancel());
    _repository = repository;
    _effects = repository?.playbacks.listen(
      (playback) => unawaited(_accept(playback)),
    );
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
