import 'dart:typed_data';

import 'zstd_bit_reader.dart';
import 'zstd_error.dart';
import 'zstd_fse.dart';
import 'zstd_tables.dart';
import 'zstd_window.dart';

/// Sequence decoding state that outlives a single block.
///
/// Both the entropy tables and the three repeat offsets carry over to the next
/// compressed block of the same frame; that is what lets an encoder spend a few
/// bits on "same tables, same offset as before" instead of redescribing them.
/// Only compressed blocks touch this state, and every frame starts fresh.
final class ZstdSequenceState {
  ZstdFseTable? literalLengths;
  ZstdFseTable? offsets;
  ZstdFseTable? matchLengths;

  int repeat1 = 1;
  int repeat2 = 4;
  int repeat3 = 8;

  void reset() {
    literalLengths = null;
    offsets = null;
    matchLengths = null;
    repeat1 = 1;
    repeat2 = 4;
    repeat3 = 8;
  }
}

/// Decodes the sequence section and replays it into [window].
///
/// The literals arrive already decoded; a sequence is "copy this many literals,
/// then repeat this many bytes from this far back", and the leftover literals
/// close the block.
void executeZstdSequences({
  required Uint8List block,
  required int start,
  required int end,
  required Uint8List literals,
  required ZstdSequenceState state,
  required ZstdWindow window,
}) {
  var cursor = start;
  if (cursor >= end) {
    zstdFail('Compressed block has no sequence section', start);
  }

  var count = block[cursor++];
  if (count > 127) {
    if (count == 255) {
      if (cursor + 2 > end) {
        zstdFail('Sequence count is truncated', cursor);
      }
      count = block[cursor] | (block[cursor + 1] << 8);
      count += 0x7f00;
      cursor += 2;
    } else {
      if (cursor >= end) {
        zstdFail('Sequence count is truncated', cursor);
      }
      count = ((count - 128) << 8) + block[cursor++];
    }
  }
  if (count == 0) {
    // A zero count ends the section on the spot: no modes byte, no bitstream.
    if (cursor != end) {
      zstdFail('Empty sequence section has trailing bytes', cursor);
    }
    window.writeBytes(literals, 0, literals.length);
    return;
  }

  if (cursor >= end) {
    zstdFail('Sequence section has no compression modes', cursor);
  }
  final modes = block[cursor++];
  if ((modes & 0x03) != 0) {
    zstdFail('Sequence modes set the reserved bits', cursor - 1);
  }

  cursor = _selectTable(
    block,
    cursor,
    end,
    (modes >> 6) & 0x03,
    'Literals length',
    zstdMaxLiteralLengthCode,
    zstdMaxLiteralLengthLog,
    zstdPredefinedLiteralLengths,
    () => state.literalLengths,
    (table) => state.literalLengths = table,
  );
  cursor = _selectTable(
    block,
    cursor,
    end,
    (modes >> 4) & 0x03,
    'Offset',
    zstdMaxOffsetCode,
    zstdMaxOffsetLog,
    zstdPredefinedOffsets,
    () => state.offsets,
    (table) => state.offsets = table,
  );
  cursor = _selectTable(
    block,
    cursor,
    end,
    (modes >> 2) & 0x03,
    'Match length',
    zstdMaxMatchLengthCode,
    zstdMaxMatchLengthLog,
    zstdPredefinedMatchLengths,
    () => state.matchLengths,
    (table) => state.matchLengths = table,
  );

  final reader = ZstdReverseBitReader(block, cursor, end);
  final literalLengthState = ZstdFseState(state.literalLengths!, reader);
  final offsetState = ZstdFseState(state.offsets!, reader);
  final matchLengthState = ZstdFseState(state.matchLengths!, reader);

  final blockStart = window.produced;
  var literalCursor = 0;
  for (var index = 0; index < count; index++) {
    final literalCode = literalLengthState.symbol;
    final matchCode = matchLengthState.symbol;
    final offsetCode = offsetState.symbol;
    if (literalCode > zstdMaxLiteralLengthCode ||
        matchCode > zstdMaxMatchLengthCode ||
        offsetCode > zstdMaxOffsetCode) {
      zstdFail('Sequence $index decoded an out of range code', start);
    }

    // Extra bits are stored offset first, then match length, then literals
    // length; the states are only advanced afterwards.
    final offsetValue = (1 << offsetCode) + reader.readBits(offsetCode);
    final matchLength =
        zstdMatchLengthBaselines[matchCode] +
        reader.readBits(zstdMatchLengthExtraBits[matchCode]);
    final literalLength =
        zstdLiteralLengthBaselines[literalCode] +
        reader.readBits(zstdLiteralLengthExtraBits[literalCode]);
    reader.requireInBounds('Sequence $index');

    if (literalCursor + literalLength > literals.length) {
      zstdFail('Sequence $index wants more literals than the block holds');
    }
    final offset = _resolveOffset(state, offsetValue, literalLength);
    window.writeBytes(literals, literalCursor, literalLength);
    literalCursor += literalLength;
    window.copyMatch(offset, matchLength);
    if (window.produced - blockStart > zstdMaxBlockSize) {
      zstdFail('Block regenerates more than $zstdMaxBlockSize bytes');
    }

    // The final sequence has no successor, so its state update was never
    // written; reading it would run off the front of the bitstream.
    if (index + 1 < count) {
      literalLengthState.update(reader);
      matchLengthState.update(reader);
      offsetState.update(reader);
      reader.requireInBounds('Sequence ${index + 1} state');
    }
  }

  window.writeBytes(literals, literalCursor, literals.length - literalCursor);
  if (window.produced - blockStart > zstdMaxBlockSize) {
    zstdFail('Block regenerates more than $zstdMaxBlockSize bytes');
  }
}

/// Reads one Symbol_Compression_Mode and leaves the table in [store].
int _selectTable(
  Uint8List block,
  int cursor,
  int end,
  int mode,
  String label,
  int maxSymbol,
  int maxAccuracyLog,
  ZstdFseTable predefined,
  ZstdFseTable? Function() load,
  void Function(ZstdFseTable) store,
) {
  switch (mode) {
    case 0:
      store(predefined);
      return cursor;
    case 1:
      if (cursor >= end) {
        zstdFail('$label RLE symbol is missing', cursor);
      }
      final symbol = block[cursor];
      if (symbol > maxSymbol) {
        zstdFail('$label RLE symbol $symbol is out of range', cursor);
      }
      store(ZstdFseTable.rle(symbol));
      return cursor + 1;
    case 2:
      final header = readZstdFseTable(
        block,
        cursor,
        end,
        maxSymbol: maxSymbol,
        maxAccuracyLog: maxAccuracyLog,
        label: label,
      );
      store(header.table);
      return cursor + header.bytesRead;
    default:
      final previous = load();
      if (previous == null) {
        zstdFail('$label table repeats but no table was ever sent', cursor);
      }
      store(previous);
      return cursor;
  }
}

/// Turns an Offset_Value into a byte distance and updates the repeat history.
int _resolveOffset(ZstdSequenceState state, int value, int literalLength) {
  if (value > 3) {
    return _promote(state, value - 3);
  }

  // With no literals in front of it a sequence cannot mean "the most recent
  // offset" — that would have been merged into the previous sequence — so the
  // repeat codes shift by one and code 3 becomes "one byte closer".
  final slot = literalLength == 0 ? value : value - 1;
  if (slot == 0) {
    return state.repeat1;
  }
  if (slot == 1) {
    final offset = state.repeat2;
    state.repeat2 = state.repeat1;
    state.repeat1 = offset;
    return offset;
  }
  if (slot == 2) {
    return _promote(state, state.repeat3);
  }
  final stepped = state.repeat1 - 1;
  if (stepped <= 0) {
    zstdFail('Repeat offset stepped below one');
  }
  return _promote(state, stepped);
}

/// Makes [offset] the most recent one, pushing the others down.
int _promote(ZstdSequenceState state, int offset) {
  state.repeat3 = state.repeat2;
  state.repeat2 = state.repeat1;
  state.repeat1 = offset;
  return offset;
}
