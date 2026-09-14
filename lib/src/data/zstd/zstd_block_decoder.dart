import 'dart:typed_data';

import 'zstd_error.dart';
import 'zstd_huffman.dart';
import 'zstd_literals.dart';
import 'zstd_sequences.dart';
import 'zstd_window.dart';

/// Block_Type values from the three byte block header.
abstract final class ZstdBlockType {
  static const raw = 0;
  static const rle = 1;
  static const compressed = 2;
  static const reserved = 3;
}

/// Decodes blocks and owns the entropy state they share.
///
/// Huffman trees and FSE tables are described once and then reused by later
/// blocks of the same frame, so this object lives as long as the frame does and
/// is cleared by [startFrame].
final class ZstdBlockDecoder {
  final ZstdSequenceState _sequences = ZstdSequenceState();
  ZstdHuffmanTable? _huffman;

  void startFrame() {
    _sequences.reset();
    _huffman = null;
  }

  /// Decodes one block into [window].
  ///
  /// [regenerated] is only meaningful for an RLE block, where the block header
  /// carries the output length and the body is a single byte.
  void decodeBlock({
    required int type,
    required int regenerated,
    required Uint8List bytes,
    required int start,
    required int end,
    required ZstdWindow window,
  }) {
    window.startBlock();
    switch (type) {
      case ZstdBlockType.raw:
        window.writeBytes(bytes, start, end - start);
      case ZstdBlockType.rle:
        if (end - start != 1) {
          zstdFail('RLE block carries ${end - start} bytes', start);
        }
        window.writeRun(bytes[start], regenerated);
      case ZstdBlockType.compressed:
        final literals = readZstdLiterals(bytes, start, end, _huffman);
        _huffman = literals.table;
        executeZstdSequences(
          block: bytes,
          start: start + literals.bytesRead,
          end: end,
          literals: literals.data,
          state: _sequences,
          window: window,
        );
      default:
        zstdFail('Block uses the reserved type', start);
    }
  }
}
