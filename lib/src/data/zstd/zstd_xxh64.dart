import 'dart:typed_data';

/// Streaming XXH64, the hash behind a frame's Content_Checksum.
///
/// Written out here because no dependency in the project provides it and the
/// checksum is the only end-to-end proof that a long-lived Gateway stream
/// decoded correctly. Dart's integers are 64-bit two's complement and wrap on
/// overflow, which is exactly the arithmetic XXH64 is defined in; the only care
/// needed is using the unsigned shift `>>>` so the avalanche steps do not drag
/// a sign bit along.
final class ZstdXxh64 {
  static const int _prime1 = 0x9e3779b185ebca87;
  static const int _prime2 = 0xc2b2ae3d27d4eb4f;
  static const int _prime3 = 0x165667b19e3779f9;
  static const int _prime4 = 0x85ebca77c2b2ae63;
  static const int _prime5 = 0x27d4eb2f165667c5;

  int _first = _prime1 + _prime2;
  int _second = _prime2;
  int _third = 0;
  int _fourth = -_prime1;

  final Uint8List _tail = Uint8List(32);
  late final ByteData _tailView = ByteData.sublistView(_tail);
  int _tailLength = 0;
  int _total = 0;

  void reset() {
    _first = _prime1 + _prime2;
    _second = _prime2;
    _third = 0;
    _fourth = -_prime1;
    _tailLength = 0;
    _total = 0;
  }

  /// Folds [data] into the running hash.
  void add(Uint8List data) {
    if (data.isEmpty) {
      return;
    }
    _total += data.length;
    final view = ByteData.sublistView(data);
    var cursor = 0;

    if (_tailLength > 0) {
      final wanted = 32 - _tailLength;
      final taken = wanted < data.length ? wanted : data.length;
      _tail.setRange(_tailLength, _tailLength + taken, data);
      _tailLength += taken;
      cursor = taken;
      if (_tailLength < 32) {
        return;
      }
      _absorb(_tailView, 0);
      _tailLength = 0;
    }

    while (cursor + 32 <= data.length) {
      _absorb(view, cursor);
      cursor += 32;
    }
    final left = data.length - cursor;
    if (left > 0) {
      _tail.setRange(0, left, data, cursor);
      _tailLength = left;
    }
  }

  /// The finished hash. Zstandard compares only its low 32 bits.
  int get digest {
    int hash;
    if (_total >= 32) {
      hash =
          _rotate(_first, 1) +
          _rotate(_second, 7) +
          _rotate(_third, 12) +
          _rotate(_fourth, 18);
      hash = _merge(hash, _first);
      hash = _merge(hash, _second);
      hash = _merge(hash, _third);
      hash = _merge(hash, _fourth);
    } else {
      hash = _prime5;
    }
    hash += _total;

    var cursor = 0;
    while (cursor + 8 <= _tailLength) {
      final lane = _round(0, _tailView.getUint64(cursor, Endian.little));
      hash ^= lane;
      hash = _rotate(hash, 27) * _prime1 + _prime4;
      cursor += 8;
    }
    if (cursor + 4 <= _tailLength) {
      hash ^= _tailView.getUint32(cursor, Endian.little) * _prime1;
      hash = _rotate(hash, 23) * _prime2 + _prime3;
      cursor += 4;
    }
    while (cursor < _tailLength) {
      hash ^= _tail[cursor] * _prime5;
      hash = _rotate(hash, 11) * _prime1;
      cursor++;
    }

    hash ^= hash >>> 33;
    hash *= _prime2;
    hash ^= hash >>> 29;
    hash *= _prime3;
    hash ^= hash >>> 32;
    return hash;
  }

  void _absorb(ByteData view, int offset) {
    _first = _round(_first, view.getUint64(offset, Endian.little));
    _second = _round(_second, view.getUint64(offset + 8, Endian.little));
    _third = _round(_third, view.getUint64(offset + 16, Endian.little));
    _fourth = _round(_fourth, view.getUint64(offset + 24, Endian.little));
  }

  static int _round(int accumulator, int lane) =>
      _rotate(accumulator + lane * _prime2, 31) * _prime1;

  static int _merge(int hash, int lane) =>
      (hash ^ _round(0, lane)) * _prime1 + _prime4;

  static int _rotate(int value, int bits) =>
      (value << bits) | (value >>> (64 - bits));
}
