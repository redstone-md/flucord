import 'zstd_codec.dart';

/// Aborts decoding with a [ZstdException].
///
/// Every failure path in the decoder funnels through this helper. A frame that
/// arrives over the Gateway is attacker-influenced data, so a malformed table,
/// a truncated bitstream, or an absurd window must never escape as a
/// `RangeError` or a silent truncation: transport code only knows how to
/// recover from [ZstdException].
Never zstdFail(String message, [int? offset]) =>
    throw ZstdException(message, null, offset);

/// Zero-based index of the most significant set bit of [value].
///
/// Both FSE table construction and Huffman weight reconstruction need
/// `floor(log2(x))`; a shared helper keeps the two from drifting apart.
int zstdHighestBit(int value) {
  if (value <= 0) {
    zstdFail('Entropy table asked for the log of $value');
  }
  var index = 0;
  var rest = value;
  while (rest > 1) {
    rest >>= 1;
    index++;
  }
  return index;
}
