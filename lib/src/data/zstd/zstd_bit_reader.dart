import 'dart:typed_data';

import 'zstd_error.dart';

/// Reads an entropy bitstream backwards, most significant bit first.
///
/// Zstandard's FSE and Huffman encoders emit their bits in reverse so that the
/// decoder can walk symbols forward. The stream therefore begins at its *last*
/// byte, whose highest set bit is a padding marker rather than data.
///
/// Reads that run past the front of the region yield zeros and set [isOverrun]
/// instead of throwing, because "the stream ran out during a state update" is
/// how FSE signals the end of a Huffman weight table — a legal condition the
/// caller has to observe, not an error the reader can decide on its own.
final class ZstdReverseBitReader {
  ZstdReverseBitReader(this._bytes, this._start, this._end) {
    if (_start < 0 || _end > _bytes.length || _end <= _start) {
      zstdFail('Entropy bitstream is empty', _start);
    }
    final marker = _bytes[_end - 1];
    if (marker == 0) {
      zstdFail('Entropy bitstream has no padding marker', _end - 1);
    }
    _capacity = (_end - _start) * 8;
    _consumed = 8 - zstdHighestBit(marker);
  }

  final Uint8List _bytes;
  final int _start;
  final int _end;
  late final int _capacity;
  int _consumed = 0;

  /// True once more bits were taken than the region holds.
  bool get isOverrun => _consumed > _capacity;

  /// Bits still unread; negative once the reader has overrun.
  int get bitsLeft => _capacity - _consumed;

  /// Returns the next [count] bits without consuming them.
  int peekBits(int count) {
    if (count <= 0) {
      return 0;
    }
    final skew = _consumed & 7;
    final head = _end - 1 - (_consumed >> 3);
    final span = (skew + count + 7) >> 3;
    var chunk = 0;
    for (var index = 0; index < span; index++) {
      final at = head - index;
      chunk = (chunk << 8) | (at >= _start && at < _end ? _bytes[at] : 0);
    }
    return (chunk >> (span * 8 - skew - count)) & ((1 << count) - 1);
  }

  void skipBits(int count) => _consumed += count;

  int readBits(int count) {
    final value = peekBits(count);
    _consumed += count;
    return value;
  }

  /// Fails when the stream was read past its end.
  void requireInBounds(String what) {
    if (isOverrun) {
      zstdFail('$what read past the end of its bitstream', _start);
    }
  }
}

/// Reads a header bitstream forwards, least significant bit first.
///
/// Only the FSE normalized-count header uses this order; it is written as a
/// little-endian bit soup that the reference decoder pulls through a sliding
/// 32-bit window. Reads past the region return zeros so the final partial byte
/// behaves like the reference's over-wide load; [bytesConsumed] is what tells
/// the caller where the header actually ended.
final class ZstdForwardBitReader {
  ZstdForwardBitReader(this._bytes, this._start, this._end) {
    if (_start < 0 || _end > _bytes.length || _end < _start) {
      zstdFail('Entropy header is out of bounds', _start);
    }
  }

  final Uint8List _bytes;
  final int _start;
  final int _end;
  int _consumed = 0;

  /// Bytes touched so far, rounded up to the next byte boundary.
  int get bytesConsumed => (_consumed + 7) >> 3;

  bool get isOverrun => _start + bytesConsumed > _end;

  int peekBits(int count) {
    if (count <= 0) {
      return 0;
    }
    final skew = _consumed & 7;
    final head = _start + (_consumed >> 3);
    final span = (skew + count + 7) >> 3;
    var chunk = 0;
    for (var index = span - 1; index >= 0; index--) {
      final at = head + index;
      chunk = (chunk << 8) | (at < _end && at >= _start ? _bytes[at] : 0);
    }
    return (chunk >> skew) & ((1 << count) - 1);
  }

  void skipBits(int count) => _consumed += count;

  int readBits(int count) {
    final value = peekBits(count);
    _consumed += count;
    return value;
  }
}
