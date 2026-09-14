import 'dart:typed_data';

/// Raised when a protobuf buffer cannot be trusted.
///
/// Everything this reader consumes arrives from the network, so a truncated or
/// hostile buffer must end as a caught exception rather than as an index that
/// walks off the end of the array or a length that drives an allocation.
final class ProtoFormatException implements Exception {
  const ProtoFormatException(this.message);

  final String message;

  @override
  String toString() => 'ProtoFormatException: $message';
}

/// The four wire types protobuf still defines.
///
/// Groups (3 and 4) were removed from the language long before any of the
/// messages Discord sends here, and 6/7 have never existed. Both are rejected
/// rather than skipped: a buffer containing one is not something we produced,
/// and guessing at its framing is how a decoder starts reading past its input.
abstract final class ProtoWireType {
  static const varint = 0;
  static const fixed64 = 1;
  static const lengthDelimited = 2;
  static const fixed32 = 5;

  static bool isSupported(int value) =>
      value == varint ||
      value == fixed64 ||
      value == lengthDelimited ||
      value == fixed32;
}

/// The largest field number protobuf allows (2^29 - 1).
const int protoMaxFieldNumber = 0x1fffffff;

/// A cursor over a protobuf buffer that refuses to read past its end.
final class ProtoReader {
  ProtoReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset >= _bytes.length;
  int get remaining => _bytes.length - _offset;

  /// Reads a base-128 varint.
  ///
  /// Ten bytes is the maximum a 64-bit value can occupy; anything longer is a
  /// buffer that would otherwise spin the shift loop forever.
  int readVarint() {
    var result = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      if (_offset >= _bytes.length) {
        throw const ProtoFormatException('Varint runs past the end of input');
      }
      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) return result;
    }
    throw const ProtoFormatException('Varint is longer than ten bytes');
  }

  int readFixed64() {
    final start = _take(8);
    var result = 0;
    for (var index = 7; index >= 0; index--) {
      result = (result << 8) | _bytes[start + index];
    }
    return result;
  }

  int readFixed32() {
    final start = _take(4);
    return _bytes[start] |
        (_bytes[start + 1] << 8) |
        (_bytes[start + 2] << 16) |
        (_bytes[start + 3] << 24);
  }

  /// Reads a length-delimited payload.
  ///
  /// The length is attacker-controlled, so it is checked against what is
  /// actually left in the buffer before it is allowed to size a view.
  Uint8List readLengthDelimited() {
    final length = readVarint();
    if (length < 0 || length > remaining) {
      throw ProtoFormatException(
        'Length-delimited field claims $length bytes but $remaining remain',
      );
    }
    final start = _take(length);
    return Uint8List.sublistView(_bytes, start, start + length);
  }

  /// Reads a field tag, returning its number and wire type.
  (int number, int wireType) readTag() {
    final tag = readVarint();
    final number = tag >>> 3;
    final wireType = tag & 0x7;
    if (tag <= 0 || number < 1 || number > protoMaxFieldNumber) {
      throw ProtoFormatException('Field number $number is out of range');
    }
    if (!ProtoWireType.isSupported(wireType)) {
      throw ProtoFormatException('Unsupported wire type $wireType');
    }
    return (number, wireType);
  }

  int _take(int length) {
    if (length > remaining) {
      throw ProtoFormatException(
        'Field needs $length bytes but $remaining remain',
      );
    }
    final start = _offset;
    _offset += length;
    return start;
  }
}

/// Builds a protobuf buffer.
final class ProtoWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeTag(int number, int wireType) {
    if (number < 1 || number > protoMaxFieldNumber) {
      throw ProtoFormatException('Field number $number is out of range');
    }
    writeVarint((number << 3) | wireType);
  }

  /// Writes a base-128 varint.
  ///
  /// Negative values are 64-bit two's complement, which protobuf spells as ten
  /// bytes, so the shift has to be unsigned or the loop never terminates.
  void writeVarint(int value) {
    var rest = value;
    while (true) {
      final byte = rest & 0x7f;
      rest = rest >>> 7;
      if (rest == 0) {
        _builder.addByte(byte);
        return;
      }
      _builder.addByte(byte | 0x80);
    }
  }

  void writeFixed64(int value) {
    final bytes = Uint8List(8);
    var rest = value;
    for (var index = 0; index < 8; index++) {
      bytes[index] = rest & 0xff;
      rest = rest >>> 8;
    }
    _builder.add(bytes);
  }

  void writeFixed32(int value) {
    final bytes = Uint8List(4);
    var rest = value;
    for (var index = 0; index < 4; index++) {
      bytes[index] = rest & 0xff;
      rest = rest >>> 8;
    }
    _builder.add(bytes);
  }

  void writeLengthDelimited(Uint8List value) {
    writeVarint(value.length);
    _builder.add(value);
  }

  Uint8List toBytes() => _builder.toBytes();
}
