import 'dart:typed_data';

/// One decoded picture, as pixels. Only the probe tool reads these: the app
/// draws decoded video on textures (ADR-0009).
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

/// A texture a decoder draws on, as it is now: the id a `Texture` widget
/// shows, and the size of the picture on it.
final class VideoTexture {
  const VideoTexture({
    required this.id,
    required this.width,
    required this.height,
  });

  final int id;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is VideoTexture &&
      other.id == id &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(id, width, height);
}

/// Turns H.264 into pictures. What a decoder does whatever it hands its
/// pictures to.
///
/// The receiving half of Go Live. Sending without this is half a feature: a
/// client that can share its screen but not watch anybody else's is not
/// something a user would call working.
abstract interface class VideoDecoder {
  bool get isSupported;

  /// The running total of access units the decoder had to drop, reported
  /// whenever it grows. A dropped unit breaks the reference chain like a lost
  /// picture: everything after it decodes against references that do not
  /// exist, so whoever feeds the decoder asks for a keyframe.
  Stream<int> get droppedAccessUnits;

  Future<void> start();

  /// Feeds one Annex B access unit in.
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp});

  Future<void> stop();
}

/// A decoder that hands every picture over as pixels, for the probe tool to
/// check what a decoder actually produced.
abstract interface class VideoDecoderService implements VideoDecoder {
  /// Pictures, in the order they decode.
  Stream<DecodedVideoFrame> get frames;
}

/// A decoder that draws its pictures on a texture, so no pixel passes
/// through Dart (ADR-0009).
///
/// After a dropped access unit the texture keeps its last whole picture
/// until a keyframe has been decoded. Whoever feeds the decoder still asks
/// for that keyframe.
abstract interface class VideoTextureDecoder implements VideoDecoder {
  /// The texture, once it has a picture, and again each time the picture
  /// changes size. One texture per [start].
  Stream<VideoTexture> get textures;
}
