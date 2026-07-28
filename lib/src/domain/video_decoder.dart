import 'dart:typed_data';

/// One decoded picture from somebody else's stream.
final class DecodedVideoFrame {
  const DecodedVideoFrame({
    required this.pixels,
    required this.width,
    required this.height,
    required this.timestamp,
  });

  /// BGRA, row-major, four bytes a pixel. The format a texture takes without
  /// further conversion.
  final Uint8List pixels;

  final int width;
  final int height;
  final Duration timestamp;

  int get expectedLength => width * height * 4;

  /// Whether the buffer holds what the dimensions claim.
  bool get isComplete => pixels.length == expectedLength;
}

/// Turns somebody else's H.264 into pictures.
///
/// The receiving half of Go Live. Sending without this is half a feature: a
/// client that can share its screen but not watch anybody else's is not
/// something a user would call working.
abstract interface class VideoDecoderService {
  bool get isSupported;

  /// Pictures, in the order they decode.
  Stream<DecodedVideoFrame> get frames;

  Future<void> start();

  /// Feeds one Annex B access unit in.
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp});

  Future<void> stop();
}
