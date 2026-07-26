import 'dart:convert';
import 'dart:typed_data';

import 'proto_wire.dart';

/// One decoded field value, still in wire terms.
sealed class ProtoValue {
  const ProtoValue();
}

final class ProtoVarint extends ProtoValue {
  const ProtoVarint(this.value);

  final int value;
}

final class ProtoFixed64 extends ProtoValue {
  const ProtoFixed64(this.value);

  final int value;
}

final class ProtoFixed32 extends ProtoValue {
  const ProtoFixed32(this.value);

  final int value;
}

final class ProtoBytes extends ProtoValue {
  const ProtoBytes(this.value);

  final Uint8List value;
}

final class ProtoField {
  const ProtoField(this.number, this.value);

  final int number;
  final ProtoValue value;
}

/// A protobuf message kept as the flat field list it arrived as.
///
/// Discord's settings blob is written back one whole top-level group at a
/// time, so a client that dropped the fields it does not model would erase
/// them on the next save. Keeping every field — in arrival order, nested
/// messages still as bytes — makes round-tripping the default rather than
/// something each mapper has to remember. Nested messages are decoded only
/// when a caller asks for one, which also means a deeply nested buffer costs
/// nothing until code that knows its shape walks into it.
final class ProtoMessage {
  ProtoMessage([List<ProtoField>? fields])
    : _fields = fields == null ? <ProtoField>[] : List.of(fields);

  final List<ProtoField> _fields;

  List<ProtoField> get fields => List.unmodifiable(_fields);
  bool get isEmpty => _fields.isEmpty;

  static ProtoMessage decode(Uint8List bytes) {
    final reader = ProtoReader(bytes);
    final fields = <ProtoField>[];
    while (!reader.isAtEnd) {
      final (number, wireType) = reader.readTag();
      fields.add(
        ProtoField(number, switch (wireType) {
          ProtoWireType.varint => ProtoVarint(reader.readVarint()),
          ProtoWireType.fixed64 => ProtoFixed64(reader.readFixed64()),
          ProtoWireType.fixed32 => ProtoFixed32(reader.readFixed32()),
          _ => ProtoBytes(reader.readLengthDelimited()),
        }),
      );
    }
    return ProtoMessage(fields);
  }

  Uint8List encode() {
    final writer = ProtoWriter();
    for (final field in _fields) {
      switch (field.value) {
        case ProtoVarint(:final value):
          writer.writeTag(field.number, ProtoWireType.varint);
          writer.writeVarint(value);
        case ProtoFixed64(:final value):
          writer.writeTag(field.number, ProtoWireType.fixed64);
          writer.writeFixed64(value);
        case ProtoFixed32(:final value):
          writer.writeTag(field.number, ProtoWireType.fixed32);
          writer.writeFixed32(value);
        case ProtoBytes(:final value):
          writer.writeTag(field.number, ProtoWireType.lengthDelimited);
          writer.writeLengthDelimited(value);
      }
    }
    return writer.toBytes();
  }

  /// A detached copy. Field values are never mutated in place, so copying the
  /// list is enough to let a caller edit one group without touching the store.
  ProtoMessage clone() => ProtoMessage(_fields);

  /// The last value carried for [number].
  ///
  /// Protobuf says the last occurrence of a singular field wins, and a merged
  /// buffer really does repeat fields, so reading the first would silently
  /// return a superseded value.
  ProtoValue? valueAt(int number) {
    for (var index = _fields.length - 1; index >= 0; index--) {
      if (_fields[index].number == number) return _fields[index].value;
    }
    return null;
  }

  int? varintAt(int number) => switch (valueAt(number)) {
    ProtoVarint(:final value) => value,
    _ => null,
  };

  bool? boolAt(int number) => switch (varintAt(number)) {
    final int value => value != 0,
    _ => null,
  };

  int? fixed64At(int number) => switch (valueAt(number)) {
    ProtoFixed64(:final value) => value,
    _ => null,
  };

  double? floatAt(int number) => switch (valueAt(number)) {
    ProtoFixed32(:final value) => _float32(value),
    _ => null,
  };

  Uint8List? bytesAt(int number) => switch (valueAt(number)) {
    ProtoBytes(:final value) => value,
    _ => null,
  };

  /// Decodes [number] as UTF-8 text, replacing malformed sequences.
  ///
  /// A settings string is display text, so a bad byte should cost a glyph
  /// rather than the whole settings load.
  String? stringAt(int number) => switch (bytesAt(number)) {
    final Uint8List value => utf8.decode(value, allowMalformed: true),
    _ => null,
  };

  ProtoMessage? messageAt(int number) => switch (bytesAt(number)) {
    final Uint8List value => ProtoMessage.decode(value),
    _ => null,
  };

  /// Reads a `google.protobuf.BoolValue`.
  ///
  /// `null` means the wrapper is absent, which is what the wrappers exist to
  /// say; a present-but-empty wrapper is the zero value, not absence.
  bool? boolWrapperAt(int number) => switch (messageAt(number)) {
    final ProtoMessage wrapper => wrapper.boolAt(1) ?? false,
    _ => null,
  };

  String? stringWrapperAt(int number) => switch (messageAt(number)) {
    final ProtoMessage wrapper => wrapper.stringAt(1) ?? '',
    _ => null,
  };

  int? intWrapperAt(int number) => switch (messageAt(number)) {
    final ProtoMessage wrapper => wrapper.varintAt(1) ?? 0,
    _ => null,
  };

  double? floatWrapperAt(int number) => switch (messageAt(number)) {
    final ProtoMessage wrapper => wrapper.floatAt(1) ?? 0.0,
    _ => null,
  };

  /// Appends [field] without touching any field already carried.
  ///
  /// Used when replaying whole groups, where the caller has already decided
  /// which numbers to drop and repeated occurrences must survive as they are.
  void addField(ProtoField field) => _fields.add(field);

  void setField(int number, ProtoValue value) {
    final index = _fields.indexWhere((field) => field.number == number);
    if (index < 0) {
      _fields.add(ProtoField(number, value));
      return;
    }
    _fields
      ..removeWhere((field) => field.number == number)
      ..insert(index, ProtoField(number, value));
  }

  void clearField(int number) =>
      _fields.removeWhere((field) => field.number == number);

  void setVarint(int number, int value) => setField(number, ProtoVarint(value));

  void setBool(int number, bool value) => setVarint(number, value ? 1 : 0);

  void setString(int number, String value) =>
      setField(number, ProtoBytes(Uint8List.fromList(utf8.encode(value))));

  void setMessage(int number, ProtoMessage value) =>
      setField(number, ProtoBytes(value.encode()));

  void setBoolWrapper(int number, bool value) =>
      setMessage(number, ProtoMessage()..setBool(1, value));

  void setStringWrapper(int number, String value) =>
      setMessage(number, ProtoMessage()..setString(1, value));

  void setIntWrapper(int number, int value) =>
      setMessage(number, ProtoMessage()..setVarint(1, value));

  static double _float32(int bits) {
    final buffer = ByteData(4)..setUint32(0, bits & 0xffffffff, Endian.little);
    return buffer.getFloat32(0, Endian.little);
  }
}
