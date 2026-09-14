/// Plays a soundboard sound out of this machine's speakers.
///
/// Deliberately separate from the voice transport: Discord does not mix a
/// soundboard sound into the RTP stream for listeners, it tells every client
/// in the channel which sound was played and each one fetches and plays it
/// locally. A client that only reported the event would show the effect and
/// stay silent.
abstract interface class SoundboardAudioPlayer {
  /// Plays the asset at [url]. Returns once playback has been started, not
  /// once it has finished.
  Future<void> play(String url, {double volume = 1});

  /// Stops anything still playing and releases the device.
  Future<void> dispose();
}
