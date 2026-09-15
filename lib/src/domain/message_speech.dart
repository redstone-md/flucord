/// Reads a message's text aloud through the machine's speakers.
///
/// Discord synthesises a spoken-aloud message on the receiving client, from
/// the text alone: the server stores no audio for it. The playback itself
/// rides the media playback layer the soundboard uses, so this contract is
/// only the synthesis half, and an implementation that cannot synthesise says
/// so rather than staying silent about being silent.
abstract interface class MessageSpeechPlayer {
  /// Whether this machine can synthesise speech at all.
  bool get isSupported;

  /// Speaks [text]. Returns once playback has been started, not finished.
  ///
  /// Returns `false` when nothing could be spoken, which is how an arriving
  /// spoken-aloud message stays a normal message on a machine with no voice,
  /// rather than becoming an error on the user's screen.
  Future<bool> speak(String text);

  /// Stops anything still being said.
  Future<void> stop();
}

/// A machine that cannot synthesise speech. Never pretends.
final class UnavailableMessageSpeechPlayer implements MessageSpeechPlayer {
  const UnavailableMessageSpeechPlayer();

  @override
  bool get isSupported => false;

  @override
  Future<bool> speak(String text) async => false;

  @override
  Future<void> stop() async {}
}
