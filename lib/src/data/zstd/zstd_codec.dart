import 'dart:typed_data';

import 'zstd_frame_decoder.dart';
import 'zstd_stream_decoder.dart';

export 'zstd_stream_decoder.dart' show ZstdStreamDecoder;

/// Raised when a Zstandard frame is malformed or uses an unsupported feature.
///
/// It extends [FormatException] so Gateway transport code keeps one decoding
/// failure path across framing, compression, and payload errors.
final class ZstdException extends FormatException {
  const ZstdException(super.message, [super.source, super.offset]);

  @override
  String toString() => 'ZstdException: $message (offset $offset)';
}

/// Pure Dart Zstandard decompression.
///
/// Discord's desktop client negotiates `compress=zstd-stream` on the Gateway
/// and decompresses with its bundled `discord_zstd` native module. Flucord
/// cannot redistribute that binary, so it implements RFC 8878 decompression
/// directly. Compression is deliberately absent: the Gateway never asks a
/// client to compress, and an unused compressor would be untestable weight.
abstract final class ZstdCodec {
  /// Largest window Flucord will allocate for a single frame.
  ///
  /// RFC 8878 permits enormous windows. Discord's Gateway never exceeds 8 MiB,
  /// so a 128 MiB ceiling rejects hostile frames long before they exhaust
  /// memory while leaving every realistic stream decodable.
  static const maxWindowLog = 27;

  /// Decodes every frame in [bytes] and concatenates their content.
  ///
  /// Skippable frames are ignored. Throws [ZstdException] on malformed input.
  static Uint8List decode(Uint8List bytes, {int maxWindowLog = maxWindowLog}) =>
      ZstdFrameDecoder(maxWindowLog: maxWindowLog).decodeAll(bytes);

  /// Creates an incremental decoder for one continuous stream.
  static ZstdStreamDecoder stream({int maxWindowLog = maxWindowLog}) =>
      ZstdStreamDecoder(maxWindowLog: maxWindowLog);
}
