import 'package:media_kit/media_kit.dart';

import '../domain/soundboard_playback.dart';

/// Plays soundboard assets through the same engine the voice-message player
/// uses.
///
/// One player is kept and re-opened rather than one per sound: creating a
/// player per effect leaks a native handle for every sound anybody plays, and
/// a busy channel plays a great many.
final class MediaKitSoundboardPlayer implements SoundboardAudioPlayer {
  MediaKitSoundboardPlayer({Player Function()? playerFactory})
    : _playerFactory = playerFactory ?? Player.new;

  /// Opened on the first sound rather than at construction: a session that
  /// never joins voice never needs an audio device, and creating one where
  /// there is none — a test host, a machine with no output — would fail at
  /// startup instead of at the moment something is actually played.
  final Player Function() _playerFactory;

  Player? _player;
  bool _disposed = false;

  @override
  Future<void> play(String url, {double volume = 1}) async {
    if (_disposed) return;
    final player = _player ??= _playerFactory();
    // Discord stores the volume as 0–1 and media_kit takes 0–100. Clamping
    // rather than trusting the payload keeps a malformed value from blasting
    // the speakers.
    await player.setVolume((volume.clamp(0, 1) * 100).toDouble());
    await player.open(Media(url));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player?.dispose();
    _player = null;
  }
}
