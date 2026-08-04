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

  /// Whether there is a picture in here worth drawing.
  ///
  /// A decoder that has been handed nothing usable still produces a buffer,
  /// and an all-zero one is not black — converted from YUV with no chroma it
  /// comes out a flat, violent green, which is what the room was showing in
  /// place of an avatar. Sampled rather than scanned: a full pass over a 4K
  /// frame, thirty times a second, to answer one question is not worth it,
  /// and a picture with content has it everywhere.
  bool get hasPicture {
    if (!isComplete || pixels.isEmpty) return false;
    // A few hundred samples spread across the buffer, whatever its size: a
    // fixed stride reads one byte of a thumbnail and thousands of a 4K frame.
    final stride = (pixels.length / 256).ceil().clamp(1, pixels.length);
    for (var index = 0; index < pixels.length; index += stride) {
      if (pixels[index] != 0) return true;
    }
    return pixels.last != 0;
  }
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
