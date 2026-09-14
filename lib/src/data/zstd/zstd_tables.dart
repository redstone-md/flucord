/// Constant tables from RFC 8878's sequence section.
///
/// They are written out in full rather than generated. A generator would hide
/// a typo behind plausible-looking arithmetic, and these values are the single
/// point where Flucord's decoder has to agree with every encoder in the world.
library;

import 'zstd_fse.dart';

/// Highest legal Literals_Length_Code.
const zstdMaxLiteralLengthCode = 35;

/// Highest legal Match_Length_Code.
const zstdMaxMatchLengthCode = 52;

/// Highest legal Offset_Code. Larger codes would imply a window no decoder
/// supports, so they are rejected rather than accommodated.
const zstdMaxOffsetCode = 31;

/// Accuracy log ceilings per section, straight from the format.
const zstdMaxLiteralLengthLog = 9;
const zstdMaxMatchLengthLog = 9;
const zstdMaxOffsetLog = 8;

/// Largest Huffman code length the literals decoder will build a table for.
const zstdMaxHuffmanBits = 12;

/// Accuracy log of the FSE table that codes Huffman weights.
const zstdMaxHuffmanWeightLog = 6;

/// A block never regenerates more than 128 KiB, whatever its header claims.
const zstdMaxBlockSize = 128 * 1024;

const List<int> _literalLengthDistribution = [
  4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, //
  2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, //
  2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1, //
];

// Codes 46..52 all carry the "less than one" probability, which is what parks
// the seven longest match lengths at the very top of the decoding table. Giving
// 46 and 47 a real count instead would shift every low-probability slot by two
// and silently decode long matches as short ones.
const List<int> _matchLengthDistribution = [
  1, 4, 3, 2, 2, 2, 2, 2, //
  2, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, -1, -1, //
  -1, -1, -1, -1, -1, //
];

const List<int> _offsetDistribution = [
  1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
  -1, -1, -1, -1, -1, //
];

/// Baseline value each Literals_Length_Code contributes before its extra bits.
const List<int> zstdLiteralLengthBaselines = [
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, //
  12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32, 40, //
  48, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, //
];

/// Extra bits read after each Literals_Length_Code.
const List<int> zstdLiteralLengthExtraBits = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, //
  4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, //
];

/// Baseline value each Match_Length_Code contributes before its extra bits.
const List<int> zstdMatchLengthBaselines = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, //
  15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, //
  27, 28, 29, 30, 31, 32, 33, 34, 35, 37, 39, 41, //
  43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, //
  4099, 8195, 16387, 32771, 65539, //
];

/// Extra bits read after each Match_Length_Code.
const List<int> zstdMatchLengthExtraBits = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, //
  2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, //
  12, 13, 14, 15, 16, //
];

/// Predefined tables are shared by every frame, so they are built once.
final ZstdFseTable zstdPredefinedLiteralLengths = ZstdFseTable.fromCounts(
  _literalLengthDistribution,
  _literalLengthDistribution.length - 1,
  6,
);

final ZstdFseTable zstdPredefinedMatchLengths = ZstdFseTable.fromCounts(
  _matchLengthDistribution,
  _matchLengthDistribution.length - 1,
  6,
);

final ZstdFseTable zstdPredefinedOffsets = ZstdFseTable.fromCounts(
  _offsetDistribution,
  _offsetDistribution.length - 1,
  5,
);
