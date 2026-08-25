import 'dart:typed_data';

/// What the far end's feedback asks of the encoder.
///
/// The share is sent from wherever its connection runs, and the encoder runs
/// on the main isolate; these are the two things the sender cannot do itself
/// and hands over instead.
sealed class GoLiveEncoderCommand {
  const GoLiveEncoderCommand();
}

/// A viewer cannot decode what is arriving and needs a fresh picture.
final class GoLiveKeyframeCommand extends GoLiveEncoderCommand {
  const GoLiveKeyframeCommand();
}

/// The bitrate the loss the far end reports allows now.
final class GoLiveBitrateCommand extends GoLiveEncoderCommand {
  const GoLiveBitrateCommand(this.bitsPerSecond);

  final int bitsPerSecond;
}

/// The share's live connection, as far as the rest of the client steers it.
abstract interface class GoLiveSender {
  /// A new bitrate target, from a quality setting rather than from loss.
  void retarget(int bitrate);

  /// One 20 ms Opus frame of the shared sound.
  void sendOpusFrame(Uint8List opus);
}
