import 'dart:typed_data';

import 'zstd_error.dart';

/// Zstandard frame magic, little endian on the wire.
const zstdFrameMagic = 0xfd2fb528;

/// Skippable frames carry application data; their magic occupies a 16 value
/// range so a producer can tag several kinds of payload.
const zstdSkippableMagicLow = 0x184d2a50;
const zstdSkippableMagicHigh = 0x184d2a5f;

/// Everything the block loop needs to know about the frame it is inside.
final class ZstdFrameHeader {
  const ZstdFrameHeader({
    required this.headerSize,
    required this.windowSize,
    required this.contentSize,
    required this.hasChecksum,
  });

  /// Bytes occupied by the magic plus the header fields.
  final int headerSize;

  /// Furthest a match may reach back.
  final int windowSize;

  /// Declared decompressed size, or null when the frame does not say.
  final int? contentSize;

  /// Whether four bytes of XXH64 follow the last block.
  final bool hasChecksum;
}

/// How many bytes the header occupies, or null when [bytes] is still too short.
///
/// The stream decoder has to know this before it can commit to parsing, since a
/// chunk may end anywhere inside the header.
int? zstdFrameHeaderSize(Uint8List bytes, int start, int end) {
  if (end - start < 5) {
    return null;
  }
  final descriptor = bytes[start + 4];
  final contentSizeFlag = descriptor >> 6;
  final singleSegment = (descriptor & 0x20) != 0;
  final dictionaryFlag = descriptor & 0x03;
  const dictionaryFieldSizes = [0, 1, 2, 4];
  final contentFieldSize = switch (contentSizeFlag) {
    0 => singleSegment ? 1 : 0,
    1 => 2,
    2 => 4,
    _ => 8,
  };
  return 5 +
      (singleSegment ? 0 : 1) +
      dictionaryFieldSizes[dictionaryFlag] +
      contentFieldSize;
}

/// Parses a complete frame header.
///
/// [maxWindowLog] is the caller's memory ceiling. Rejecting an oversized window
/// here — before a single block is read — is what keeps a hostile frame from
/// making Flucord allocate hundreds of megabytes.
ZstdFrameHeader readZstdFrameHeader(
  Uint8List bytes,
  int start,
  int end, {
  required int maxWindowLog,
}) {
  final size = zstdFrameHeaderSize(bytes, start, end);
  if (size == null || start + size > end) {
    zstdFail('Frame header is truncated', start);
  }
  final descriptor = bytes[start + 4];
  if ((descriptor & 0x08) != 0) {
    zstdFail('Frame header sets the reserved bit', start + 4);
  }
  final contentSizeFlag = descriptor >> 6;
  final singleSegment = (descriptor & 0x20) != 0;
  final hasChecksum = (descriptor & 0x04) != 0;
  final dictionaryFlag = descriptor & 0x03;

  var cursor = start + 5;
  var windowSize = 0;
  if (!singleSegment) {
    final window = bytes[cursor++];
    final exponent = window >> 3;
    final mantissa = window & 0x07;
    final windowLog = 10 + exponent;
    if (windowLog > 31) {
      zstdFail(
        'Frame declares an impossible window log $windowLog',
        cursor - 1,
      );
    }
    final base = 1 << windowLog;
    windowSize = base + (base >> 3) * mantissa;
  }

  if (dictionaryFlag != 0) {
    var dictionaryId = 0;
    final width = const [0, 1, 2, 4][dictionaryFlag];
    for (var index = 0; index < width; index++) {
      dictionaryId |= bytes[cursor + index] << (8 * index);
    }
    cursor += width;
    if (dictionaryId != 0) {
      zstdFail('Dictionary $dictionaryId is not supported', cursor - width);
    }
  }

  int? contentSize;
  final contentFieldSize = switch (contentSizeFlag) {
    0 => singleSegment ? 1 : 0,
    1 => 2,
    2 => 4,
    _ => 8,
  };
  if (contentFieldSize > 0) {
    var value = 0;
    for (var index = 0; index < contentFieldSize; index++) {
      value |= bytes[cursor + index] << (8 * index);
    }
    cursor += contentFieldSize;
    // The two byte form starts at 256 because anything smaller fits the one
    // byte form, which buys the encoder an extra 256 values of range.
    contentSize = contentFieldSize == 2 ? value + 256 : value;
    if (contentSize < 0) {
      zstdFail('Frame content size does not fit a 63 bit integer', cursor);
    }
  }

  if (singleSegment) {
    windowSize = contentSize ?? 0;
  }
  final ceiling = 1 << maxWindowLog;
  if (windowSize > ceiling) {
    zstdFail(
      'Frame needs a $windowSize byte window, ceiling is $ceiling',
      start,
    );
  }

  return ZstdFrameHeader(
    headerSize: cursor - start,
    windowSize: windowSize,
    contentSize: contentSize,
    hasChecksum: hasChecksum,
  );
}
