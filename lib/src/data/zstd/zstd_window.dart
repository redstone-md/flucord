import 'dart:typed_data';

import 'zstd_error.dart';
import 'zstd_tables.dart';

/// The decompressed history a frame's matches can reach back into.
///
/// A Gateway connection is one long frame, so keeping every byte ever produced
/// is not an option. The buffer instead holds at most `Window_Size` bytes of
/// history plus the block being written, and old bytes are dropped once they
/// fall out of reach. Dropping happens between blocks, when everything has been
/// handed to the caller, so a match can always look back the full window even
/// from the last byte of a block.
///
/// It grows on demand rather than allocating `Window_Size` up front: a frame
/// may declare a 128 MiB window and then send two kilobytes.
final class ZstdWindow {
  ZstdWindow({required this.windowSize});

  final int windowSize;

  Uint8List _buffer = Uint8List(0);
  int _length = 0;
  int _pending = 0;
  int _produced = 0;

  /// Total bytes this frame has decompressed so far.
  int get produced => _produced;

  /// Bytes written since the last [takeOutput].
  int get pendingLength => _length - _pending;

  /// Slack retained above `Window_Size` before history is compacted.
  ///
  /// Compacting as soon as the window is one byte over would move
  /// `Window_Size` bytes for every block, so a peer could send thousands of
  /// tiny blocks and make an 8 MiB window cost gigabytes of copying. Letting
  /// the buffer run a whole window past the limit means each compaction is
  /// paid for by at least as many new bytes, which keeps the cost amortized
  /// constant per byte.
  int get _compactionSlack => windowSize < 65536 ? 65536 : windowSize;

  /// Releases history that no sequence can legally reference any more.
  void startBlock() {
    if (_pending != _length) return;
    final dropped = _length - windowSize;
    if (dropped < _compactionSlack) return;
    _buffer.setRange(0, windowSize, _buffer, dropped);
    _length = windowSize;
    _pending = windowSize;
  }

  void _reserve(int extra) {
    final needed = _length + extra;
    if (needed <= _buffer.length) {
      return;
    }
    var capacity = _buffer.isEmpty ? 4096 : _buffer.length;
    while (capacity < needed) {
      capacity *= 2;
    }
    final grown = Uint8List(capacity);
    grown.setRange(0, _length, _buffer);
    _buffer = grown;
  }

  /// Appends literal bytes taken straight from the compressed frame.
  void writeBytes(Uint8List source, int start, int length) {
    if (length == 0) {
      return;
    }
    if (start < 0 || length < 0 || start + length > source.length) {
      zstdFail('Literal run of $length bytes is not in the block', start);
    }
    _reserve(length);
    _buffer.setRange(_length, _length + length, source, start);
    _length += length;
    _produced += length;
  }

  /// Appends [count] copies of [value], the payload of an RLE block.
  void writeRun(int value, int count) {
    if (count == 0) {
      return;
    }
    _reserve(count);
    _buffer.fillRange(_length, _length + count, value);
    _length += count;
    _produced += count;
  }

  /// Copies [length] bytes from [offset] bytes back in the history.
  ///
  /// When the match overlaps itself the copy has to be byte by byte: an
  /// `offset` of one is how the format spells "repeat this byte", and a bulk
  /// move would read the destination before it was written.
  void copyMatch(int offset, int length) {
    if (offset <= 0) {
      zstdFail('Match offset $offset is not positive');
    }
    if (offset > windowSize) {
      zstdFail('Match offset $offset exceeds the $windowSize byte window');
    }
    if (offset > _length) {
      zstdFail('Match offset $offset reaches before the start of the frame');
    }
    if (length < 0 || length > zstdMaxBlockSize * 2) {
      zstdFail('Match length $length is out of range');
    }
    _reserve(length);
    var from = _length - offset;
    if (offset >= length) {
      _buffer.setRange(_length, _length + length, _buffer, from);
      _length += length;
    } else {
      for (var index = 0; index < length; index++) {
        _buffer[_length++] = _buffer[from++];
      }
    }
    _produced += length;
  }

  /// Hands back everything produced since the previous call.
  Uint8List takeOutput() {
    final count = _length - _pending;
    if (count == 0) {
      return Uint8List(0);
    }
    final output = Uint8List(count);
    output.setRange(0, count, _buffer, _pending);
    _pending = _length;
    return output;
  }
}
