import 'dart:typed_data';

import 'zstd_block_decoder.dart';
import 'zstd_error.dart';
import 'zstd_frame_header.dart';
import 'zstd_window.dart';
import 'zstd_xxh64.dart';

/// Largest block a conforming encoder may emit.
const zstdBlockMaximumSize = 128 * 1024;

/// Decodes complete Zstandard frames out of a buffer.
///
/// A buffer may hold several frames back to back and may interleave skippable
/// frames, which is how producers embed their own metadata. Concatenating the
/// content of every real frame is what the format defines decompression to
/// mean, so partial handling here would silently drop data.
final class ZstdFrameDecoder {
  ZstdFrameDecoder({required this.maxWindowLog});

  final int maxWindowLog;

  final ZstdBlockDecoder _blocks = ZstdBlockDecoder();
  final ZstdXxh64 _checksum = ZstdXxh64();

  /// Decodes every frame in [bytes] and concatenates their content.
  Uint8List decodeAll(Uint8List bytes) {
    final output = BytesBuilder(copy: false);
    var cursor = 0;
    while (cursor < bytes.length) {
      cursor = _decodeFrame(bytes, cursor, output);
    }
    return output.takeBytes();
  }

  int _decodeFrame(Uint8List bytes, int start, BytesBuilder output) {
    if (bytes.length - start < 4) {
      zstdFail('Frame magic is truncated', start);
    }
    final view = ByteData.sublistView(bytes);
    final magic = view.getUint32(start, Endian.little);

    if (magic >= zstdSkippableMagicLow && magic <= zstdSkippableMagicHigh) {
      if (bytes.length - start < 8) {
        zstdFail('Skippable frame header is truncated', start);
      }
      final size = view.getUint32(start + 4, Endian.little);
      final next = start + 8 + size;
      if (next > bytes.length) {
        zstdFail('Skippable frame runs past the buffer', start);
      }
      return next;
    }
    if (magic != zstdFrameMagic) {
      zstdFail('Buffer does not start with a Zstandard frame', start);
    }

    final header = readZstdFrameHeader(
      bytes,
      start,
      bytes.length,
      maxWindowLog: maxWindowLog,
    );
    final window = ZstdWindow(windowSize: header.windowSize);
    _blocks.startFrame();
    if (header.hasChecksum) _checksum.reset();

    var cursor = start + header.headerSize;
    var last = false;
    while (!last) {
      if (bytes.length - cursor < 3) {
        zstdFail('Block header is truncated', cursor);
      }
      final descriptor =
          bytes[cursor] | (bytes[cursor + 1] << 8) | (bytes[cursor + 2] << 16);
      last = (descriptor & 1) != 0;
      final type = (descriptor >> 1) & 3;
      final size = descriptor >> 3;
      cursor += 3;
      if (size > zstdBlockMaximumSize) {
        zstdFail('Block declares $size bytes, over the format maximum', cursor);
      }
      // For an RLE block the header size is the *regenerated* length and the
      // body is a single byte. Treating it as a body length rejects valid
      // frames and, worse, desynchronises the cursor for everything after.
      final bodySize = type == ZstdBlockType.rle ? 1 : size;
      if (cursor + bodySize > bytes.length) {
        zstdFail('Block body runs past the buffer', cursor);
      }
      _blocks.decodeBlock(
        type: type,
        regenerated: size,
        bytes: bytes,
        start: cursor,
        end: cursor + bodySize,
        window: window,
      );
      cursor += bodySize;
      _drain(window, output, header.hasChecksum);
    }

    final produced = window.produced;
    final declared = header.contentSize;
    if (declared != null && declared != produced) {
      zstdFail('Frame declared $declared bytes but produced $produced', cursor);
    }
    if (header.hasChecksum) {
      if (cursor + 4 > bytes.length) {
        zstdFail('Content checksum is truncated', cursor);
      }
      final expected = view.getUint32(cursor, Endian.little);
      final actual = _checksum.digest & 0xffffffff;
      if (expected != actual) {
        zstdFail('Content checksum does not match the decoded data', cursor);
      }
      cursor += 4;
    }
    return cursor;
  }

  void _drain(ZstdWindow window, BytesBuilder output, bool hashing) {
    final produced = window.takeOutput();
    if (produced.isEmpty) return;
    if (hashing) _checksum.add(produced);
    output.add(produced);
  }
}
