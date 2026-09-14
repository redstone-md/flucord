import 'dart:typed_data';

import 'zstd_bit_reader.dart';
import 'zstd_error.dart';

/// A finite state entropy decoding table.
///
/// One entry per state: the symbol it emits, how many bits the next transition
/// consumes, and the base the freshly read bits are added to. Keeping the three
/// in parallel typed arrays makes the hot loop a pair of indexed loads.
final class ZstdFseTable {
  ZstdFseTable._(this.accuracyLog, this.symbols, this.newStates, this.bitCounts)
    : size = symbols.length;

  /// A degenerate table for RLE mode: one state that always emits [symbol].
  factory ZstdFseTable.rle(int symbol) => ZstdFseTable._(
    0,
    Uint8List.fromList([symbol]),
    Uint16List(1),
    Uint8List(1),
  );

  /// Builds a table from a normalized distribution.
  ///
  /// The two rules that are easy to get wrong are both here: symbols with a
  /// "less than one" probability (`-1`) are parked at the top of the table
  /// before anything else is spread, and the spread step deliberately skips
  /// over that reserved tail so those slots survive.
  factory ZstdFseTable.fromCounts(
    List<int> counts,
    int maxSymbol,
    int accuracyLog,
  ) {
    final size = 1 << accuracyLog;
    final symbols = Uint8List(size);
    final newStates = Uint16List(size);
    final bitCounts = Uint8List(size);
    final next = List<int>.filled(maxSymbol + 1, 0);

    var highThreshold = size - 1;
    var total = 0;
    for (var symbol = 0; symbol <= maxSymbol; symbol++) {
      final count = counts[symbol];
      if (count == -1) {
        symbols[highThreshold--] = symbol;
        next[symbol] = 1;
        total += 1;
      } else {
        next[symbol] = count;
        total += count;
      }
    }
    if (total != size) {
      zstdFail('FSE distribution sums to $total, expected $size');
    }

    final step = (size >> 1) + (size >> 3) + 3;
    final mask = size - 1;
    var position = 0;
    for (var symbol = 0; symbol <= maxSymbol; symbol++) {
      for (var repeat = 0; repeat < counts[symbol]; repeat++) {
        symbols[position] = symbol;
        do {
          position = (position + step) & mask;
        } while (position > highThreshold);
      }
    }
    if (position != 0) {
      zstdFail('FSE table spread did not close its cycle');
    }

    for (var state = 0; state < size; state++) {
      final symbol = symbols[state];
      final nextState = next[symbol]++;
      final bits = accuracyLog - zstdHighestBit(nextState);
      bitCounts[state] = bits;
      newStates[state] = (nextState << bits) - size;
    }
    return ZstdFseTable._(accuracyLog, symbols, newStates, bitCounts);
  }

  final int accuracyLog;
  final int size;
  final Uint8List symbols;
  final Uint16List newStates;
  final Uint8List bitCounts;
}

/// An FSE table plus the number of header bytes it occupied.
typedef ZstdFseHeader = ({ZstdFseTable table, int bytesRead});

/// Decodes a normalized-count header and builds the matching table.
///
/// [maxSymbol] and [maxAccuracyLog] are the per-section limits from the format;
/// enforcing them here keeps a hostile header from allocating a huge table or
/// writing past the count array.
ZstdFseHeader readZstdFseTable(
  Uint8List bytes,
  int start,
  int end, {
  required int maxSymbol,
  required int maxAccuracyLog,
  required String label,
}) {
  final reader = ZstdForwardBitReader(bytes, start, end);
  final accuracyLog = reader.readBits(4) + 5;
  if (accuracyLog > maxAccuracyLog) {
    zstdFail(
      '$label FSE accuracy log $accuracyLog exceeds $maxAccuracyLog',
      start,
    );
  }

  final counts = List<int>.filled(maxSymbol + 1, 0);
  var remaining = (1 << accuracyLog) + 1;
  var threshold = 1 << accuracyLog;
  var width = accuracyLog + 1;
  var symbol = 0;
  var previousWasZero = false;

  while (remaining > 1 && symbol <= maxSymbol) {
    if (previousWasZero) {
      // A zero probability is followed by a run length in 2-bit groups, where
      // a group of three means "three more zeroes, keep reading".
      var skipped = 0;
      while (reader.peekBits(2) == 3) {
        reader.skipBits(2);
        skipped += 3;
        if (symbol + skipped > maxSymbol + 1) {
          zstdFail('$label FSE header skips past symbol $maxSymbol', start);
        }
      }
      skipped += reader.readBits(2);
      symbol += skipped;
      previousWasZero = false;
      if (symbol > maxSymbol + 1) {
        zstdFail('$label FSE header skips past symbol $maxSymbol', start);
      }
      if (symbol > maxSymbol) {
        break;
      }
    }

    // Probabilities are written with a variable width so the small values that
    // dominate a distribution cost one bit less than the wide ones.
    final ceiling = (2 * threshold - 1) - remaining;
    final raw = reader.peekBits(width);
    int count;
    if ((raw & (threshold - 1)) < ceiling) {
      count = raw & (threshold - 1);
      reader.skipBits(width - 1);
    } else {
      count = raw & (2 * threshold - 1);
      if (count >= threshold) {
        count -= ceiling;
      }
      reader.skipBits(width);
    }
    count -= 1;
    remaining -= count < 0 ? -count : count;
    if (remaining < 0) {
      zstdFail('$label FSE distribution overflows its table', start);
    }
    counts[symbol] = count;
    symbol++;
    previousWasZero = count == 0;
    while (remaining < threshold) {
      width--;
      threshold >>= 1;
    }
  }

  if (remaining != 1) {
    zstdFail('$label FSE distribution is incomplete', start);
  }
  if (reader.isOverrun) {
    zstdFail('$label FSE header runs past the section', start);
  }
  return (
    table: ZstdFseTable.fromCounts(counts, symbol - 1, accuracyLog),
    bytesRead: reader.bytesConsumed,
  );
}

/// One interleaved FSE decoder riding a shared reverse bitstream.
final class ZstdFseState {
  ZstdFseState(this.table, ZstdReverseBitReader reader)
    : _state = reader.readBits(table.accuracyLog) {
    _check();
  }

  final ZstdFseTable table;
  int _state;

  int get symbol => table.symbols[_state];

  void update(ZstdReverseBitReader reader) {
    _state = table.newStates[_state] + reader.readBits(table.bitCounts[_state]);
    _check();
  }

  void _check() {
    if (_state < 0 || _state >= table.size) {
      zstdFail('FSE state $_state escaped a table of ${table.size} entries');
    }
  }
}
