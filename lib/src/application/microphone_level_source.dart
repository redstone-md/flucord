/// How loud the microphone is right now, for a meter to draw.
abstract interface class MicrophoneLevelSource {
  /// One reading per 20 ms frame, in dB relative to full scale; silence is
  /// minus infinity.
  ///
  /// Listening is what holds the microphone: it opens when nothing else has
  /// it open, and cancelling the last subscription lets it go again unless a
  /// call is using it. A microphone that will not open arrives as an error.
  Stream<double> get inputLevels;
}
