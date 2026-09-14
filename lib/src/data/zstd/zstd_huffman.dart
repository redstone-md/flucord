import 'dart:typed_data';

import 'zstd_bit_reader.dart';
import 'zstd_error.dart';
import 'zstd_fse.dart';
import 'zstd_tables.dart';

/// A flattened Huffman decoding table for one literals section.
///
/// Instead of walking a tree, the decoder peeks [maxBits] bits and uses them as
/// an index: every code of `n` bits owns `2^(maxBits - n)` consecutive slots.
/// That makes a symbol one array read plus one bit skip, which matters because
/// literals are by far the most numerous thing in a Gateway payload.
final class ZstdHuffmanTable {
  ZstdHuffmanTable._(this.maxBits, this.symbols, this.bitCounts);

  final int maxBits;
  final Uint8List symbols;
  final Uint8List bitCounts;
}

/// A parsed Huffman tree description plus the bytes it occupied.
typedef ZstdHuffmanHeader = ({ZstdHuffmanTable table, int bytesRead});

/// Reads a Huffman_Tree_Description starting at [start].
ZstdHuffmanHeader readZstdHuffmanTable(Uint8List bytes, int start, int end) {
  if (start >= end) {
    zstdFail('Huffman tree description is missing', start);
  }
  final head = bytes[start];
  // Two slots of slack: the FSE path writes weights in pairs and the implied
  // final weight is appended after the last decoded one.
  final weights = Uint8List(258);
  final int count;
  final int bytesRead;
  if (head >= 128) {
    // Direct representation: one 4-bit weight per nibble, high nibble first.
    count = head - 127;
    final packed = (count + 1) >> 1;
    if (start + 1 + packed > end) {
      zstdFail('Huffman weights are truncated', start);
    }
    for (var index = 0; index < count; index++) {
      final byte = bytes[start + 1 + (index >> 1)];
      weights[index] = index.isEven ? byte >> 4 : byte & 0x0f;
    }
    bytesRead = 1 + packed;
  } else {
    if (start + 1 + head > end) {
      zstdFail('Huffman weight bitstream is truncated', start);
    }
    count = _readFseWeights(bytes, start + 1, start + 1 + head, weights);
    bytesRead = 1 + head;
  }
  return (table: _buildTable(weights, count), bytesRead: bytesRead);
}

/// Decodes the weight list written as an FSE bitstream.
///
/// The weight count is not stored anywhere: decoding stops when the two
/// interleaved states run the bitstream dry, and the state that has not yet
/// been read contributes the final weight.
int _readFseWeights(Uint8List bytes, int start, int end, Uint8List weights) {
  final header = readZstdFseTable(
    bytes,
    start,
    end,
    maxSymbol: zstdMaxHuffmanBits,
    maxAccuracyLog: zstdMaxHuffmanWeightLog,
    label: 'Huffman weight',
  );
  final reader = ZstdReverseBitReader(bytes, start + header.bytesRead, end);
  final first = ZstdFseState(header.table, reader);
  final second = ZstdFseState(header.table, reader);

  var count = 0;
  while (true) {
    if (count > 255) {
      zstdFail('Huffman tree describes more than 255 weights', start);
    }
    weights[count++] = first.symbol;
    first.update(reader);
    if (reader.isOverrun) {
      weights[count++] = second.symbol;
      break;
    }
    weights[count++] = second.symbol;
    second.update(reader);
    if (reader.isOverrun) {
      weights[count++] = first.symbol;
      break;
    }
  }
  return count;
}

/// Turns weights into code lengths and lays out the decoding table.
ZstdHuffmanTable _buildTable(Uint8List weights, int count) {
  if (count < 1 || count > 255) {
    zstdFail('Huffman tree has $count weights');
  }
  var total = 0;
  for (var index = 0; index < count; index++) {
    final weight = weights[index];
    if (weight > zstdMaxHuffmanBits) {
      zstdFail('Huffman weight $weight is out of range');
    }
    if (weight > 0) {
      total += 1 << (weight - 1);
    }
  }
  if (total == 0) {
    zstdFail('Huffman tree assigns no codes');
  }

  // The tree is always complete, so the last symbol's weight is whatever fills
  // the remaining space of the next power of two.
  final maxBits = zstdHighestBit(total) + 1;
  if (maxBits > zstdMaxHuffmanBits) {
    zstdFail('Huffman code length $maxBits exceeds $zstdMaxHuffmanBits');
  }
  final rest = (1 << maxBits) - total;
  if ((rest & (rest - 1)) != 0) {
    zstdFail('Huffman weights do not complete the tree');
  }
  weights[count] = zstdHighestBit(rest) + 1;
  final symbolCount = count + 1;

  final size = 1 << maxBits;
  final symbols = Uint8List(size);
  final bitCounts = Uint8List(size);
  var position = 0;
  // Codes are handed out starting from the *lowest* weight, which means the
  // longest codes occupy the low end of the table and the shortest ones the
  // high end. Filling the other way round still produces a complete table, so
  // the mistake only shows up as plausible-looking garbage literals.
  for (var weight = 1; weight <= maxBits; weight++) {
    final bits = maxBits + 1 - weight;
    final span = 1 << (weight - 1);
    for (var symbol = 0; symbol < symbolCount; symbol++) {
      if (weights[symbol] != weight) {
        continue;
      }
      if (position + span > size) {
        zstdFail('Huffman table overflows $size slots');
      }
      symbols.fillRange(position, position + span, symbol);
      bitCounts.fillRange(position, position + span, bits);
      position += span;
    }
  }
  if (position != size) {
    zstdFail('Huffman table leaves $size slots partly unassigned');
  }
  return ZstdHuffmanTable._(maxBits, symbols, bitCounts);
}

/// Decodes [count] literals from a single Huffman bitstream.
void decodeZstdHuffmanStream(
  ZstdHuffmanTable table,
  Uint8List bytes,
  int start,
  int end,
  Uint8List destination,
  int destinationStart,
  int count,
) {
  if (count == 0) {
    return;
  }
  final reader = ZstdReverseBitReader(bytes, start, end);
  final maxBits = table.maxBits;
  var at = destinationStart;
  for (var index = 0; index < count; index++) {
    final slot = reader.peekBits(maxBits);
    destination[at++] = table.symbols[slot];
    reader.skipBits(table.bitCounts[slot]);
  }
  reader.requireInBounds('Huffman literals');
}

/// Decodes literals split across the four independently seekable streams.
///
/// The jump table only sizes the first three; the fourth takes whatever is
/// left, which is also the only bound that stops a malformed table from
/// pointing a stream outside the section.
void decodeZstdHuffmanStreams(
  ZstdHuffmanTable table,
  Uint8List bytes,
  int start,
  int end,
  Uint8List destination,
  int count,
) {
  if (end - start < 6) {
    zstdFail('Huffman jump table is truncated', start);
  }
  final first = bytes[start] | (bytes[start + 1] << 8);
  final second = bytes[start + 2] | (bytes[start + 3] << 8);
  final third = bytes[start + 4] | (bytes[start + 5] << 8);
  final body = start + 6;
  final fourth = end - body - first - second - third;
  if (fourth < 0) {
    zstdFail('Huffman jump table overruns the literals section', start);
  }

  final segment = (count + 3) >> 2;
  final last = count - 3 * segment;
  if (last < 0) {
    zstdFail('Huffman streams cannot cover $count literals', start);
  }
  final sizes = [first, second, third, fourth];
  final counts = [segment, segment, segment, last];
  var offset = body;
  for (var stream = 0; stream < 4; stream++) {
    decodeZstdHuffmanStream(
      table,
      bytes,
      offset,
      offset + sizes[stream],
      destination,
      stream * segment,
      counts[stream],
    );
    offset += sizes[stream];
  }
}
