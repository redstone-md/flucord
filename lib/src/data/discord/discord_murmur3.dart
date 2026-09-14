import 'dart:convert';
import 'dart:typed_data';

/// MurmurHash3 x86 32-bit.
///
/// Discord's renderer derives a channel's member-list identifier by hashing its
/// permission overwrites with the `murmurhash` package's `v3` entry point,
/// which is this algorithm over UTF-8 bytes with seed `0`. Reproducing the hash
/// exactly is what lets Flucord match an inbound `GUILD_MEMBER_LIST_UPDATE` to
/// the channel it subscribed, so this is protocol code, not a utility.
abstract final class DiscordMurmur3 {
  static const _c1 = 0xcc9e2d51;
  static const _c2 = 0x1b873593;
  static const _mask = 0xffffffff;

  /// Hashes the UTF-8 encoding of [text].
  static int hashText(String text, {int seed = 0}) =>
      hashBytes(utf8.encode(text), seed: seed);

  /// Hashes [bytes] and returns an unsigned 32-bit result.
  static int hashBytes(List<int> bytes, {int seed = 0}) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blocks = data.length ~/ 4;
    var hash = seed & _mask;

    for (var block = 0; block < blocks; block++) {
      final index = block * 4;
      final chunk =
          data[index] |
          (data[index + 1] << 8) |
          (data[index + 2] << 16) |
          (data[index + 3] << 24);
      hash = _mixBlock(hash, chunk);
    }

    var tail = 0;
    final remainder = data.length & 3;
    final tailStart = blocks * 4;
    if (remainder == 3) tail ^= data[tailStart + 2] << 16;
    if (remainder >= 2) tail ^= data[tailStart + 1] << 8;
    if (remainder >= 1) {
      tail ^= data[tailStart];
      hash ^= _scramble(tail);
    }

    return _finalize(hash ^ data.length);
  }

  static int _mixBlock(int hash, int chunk) {
    final mixed = hash ^ _scramble(chunk);
    final rotated = _rotateLeft(mixed, 13);
    return (rotated * 5 + 0xe6546b64) & _mask;
  }

  static int _scramble(int chunk) {
    final scaled = (chunk * _c1) & _mask;
    return (_rotateLeft(scaled, 15) * _c2) & _mask;
  }

  static int _finalize(int hash) {
    var value = hash & _mask;
    value ^= value >>> 16;
    value = (value * 0x85ebca6b) & _mask;
    value ^= value >>> 13;
    value = (value * 0xc2b2ae35) & _mask;
    return (value ^ (value >>> 16)) & _mask;
  }

  static int _rotateLeft(int value, int bits) =>
      ((value << bits) | (value >>> (32 - bits))) & _mask;
}
