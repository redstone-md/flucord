import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/data/proto/proto_wire.dart';

void main() {
  group('ProtoReader', () {
    test('reads every wire type it supports', () {
      final writer = ProtoWriter()
        ..writeTag(1, ProtoWireType.varint)
        ..writeVarint(300)
        ..writeTag(2, ProtoWireType.fixed64)
        ..writeFixed64(0x0102030405060708)
        ..writeTag(3, ProtoWireType.fixed32)
        ..writeFixed32(0x7f0000ff)
        ..writeTag(4, ProtoWireType.lengthDelimited)
        ..writeLengthDelimited(Uint8List.fromList(utf8.encode('flucord')));
      final reader = ProtoReader(writer.toBytes());

      expect(reader.readTag(), (1, ProtoWireType.varint));
      expect(reader.readVarint(), 300);
      expect(reader.readTag(), (2, ProtoWireType.fixed64));
      expect(reader.readFixed64(), 0x0102030405060708);
      expect(reader.readTag(), (3, ProtoWireType.fixed32));
      expect(reader.readFixed32(), 0x7f0000ff);
      expect(reader.readTag(), (4, ProtoWireType.lengthDelimited));
      expect(utf8.decode(reader.readLengthDelimited()), 'flucord');
      expect(reader.isAtEnd, isTrue);
    });

    test('round-trips a negative varint as ten bytes', () {
      final writer = ProtoWriter()..writeVarint(-2);
      final bytes = writer.toBytes();

      expect(bytes.length, 10);
      expect(ProtoReader(bytes).readVarint(), -2);
    });

    test('rejects a varint that never terminates', () {
      final bytes = Uint8List.fromList(List.filled(12, 0xff));

      expect(
        () => ProtoReader(bytes).readVarint(),
        throwsA(
          isA<ProtoFormatException>().having(
            (error) => error.message,
            'message',
            contains('ten bytes'),
          ),
        ),
      );
    });

    test('rejects a varint that runs off the end', () {
      expect(
        () => ProtoReader(Uint8List.fromList([0x80])).readVarint(),
        throwsA(isA<ProtoFormatException>()),
      );
    });

    test('rejects a length that claims more than the buffer holds', () {
      // Field 1, length-delimited, declaring 40 bytes with 2 present.
      final bytes = Uint8List.fromList([0x0a, 40, 1, 2]);

      expect(() => ProtoReader(bytes).readTag(), returnsNormally);
      expect(
        () => ProtoMessage.decode(bytes),
        throwsA(
          isA<ProtoFormatException>().having(
            (error) => error.message,
            'message',
            contains('40 bytes'),
          ),
        ),
      );
    });

    test('rejects a truncated fixed field', () {
      expect(
        () => ProtoReader(Uint8List.fromList([1, 2, 3])).readFixed64(),
        throwsA(isA<ProtoFormatException>()),
      );
      expect(
        () => ProtoReader(Uint8List.fromList([1])).readFixed32(),
        throwsA(isA<ProtoFormatException>()),
      );
    });

    test('rejects a group wire type and a zero field number', () {
      // Tag 0x0b is field 1 with wire type 3 (start group).
      expect(
        () => ProtoReader(Uint8List.fromList([0x0b])).readTag(),
        throwsA(
          isA<ProtoFormatException>().having(
            (error) => error.message,
            'message',
            contains('wire type 3'),
          ),
        ),
      );
      expect(
        () => ProtoReader(Uint8List.fromList([0x00])).readTag(),
        throwsA(
          isA<ProtoFormatException>().having(
            (error) => error.message,
            'message',
            contains('out of range'),
          ),
        ),
      );
    });

    test('rejects a field number past the protobuf ceiling', () {
      // A tag whose top bit is set decodes to a negative int, which shifts to
      // a field number far beyond 2^29-1.
      final writer = ProtoWriter()..writeVarint(-1);

      expect(
        () => ProtoReader(writer.toBytes()).readTag(),
        throwsA(isA<ProtoFormatException>()),
      );
    });

    test('reports remaining bytes', () {
      final reader = ProtoReader(Uint8List.fromList([1, 2, 3]));

      expect(reader.remaining, 3);
      reader.readVarint();
      expect(reader.remaining, 2);
    });
  });

  group('ProtoWriter', () {
    test('refuses an out-of-range field number', () {
      expect(
        () => ProtoWriter().writeTag(0, ProtoWireType.varint),
        throwsA(isA<ProtoFormatException>()),
      );
      expect(
        () => ProtoWriter().writeTag(
          protoMaxFieldNumber + 1,
          ProtoWireType.varint,
        ),
        throwsA(isA<ProtoFormatException>()),
      );
    });

    test('describes itself when thrown', () {
      expect(
        const ProtoFormatException('bad').toString(),
        'ProtoFormatException: bad',
      );
    });
  });

  group('ProtoMessage', () {
    test('round-trips every accessor', () {
      final message = ProtoMessage()
        ..setVarint(1, 42)
        ..setBool(2, true)
        ..setString(3, 'hello')
        ..setMessage(4, ProtoMessage()..setVarint(1, 7))
        ..setBoolWrapper(5, false)
        ..setStringWrapper(6, 'wrapped')
        ..setIntWrapper(7, 900)
        ..setField(8, const ProtoFixed64(1234567890123))
        ..setField(9, const ProtoFixed32(0x3f800000));

      final decoded = ProtoMessage.decode(message.encode());

      expect(decoded.varintAt(1), 42);
      expect(decoded.boolAt(2), isTrue);
      expect(decoded.stringAt(3), 'hello');
      expect(decoded.messageAt(4)?.varintAt(1), 7);
      expect(decoded.boolWrapperAt(5), isFalse);
      expect(decoded.stringWrapperAt(6), 'wrapped');
      expect(decoded.intWrapperAt(7), 900);
      expect(decoded.fixed64At(8), 1234567890123);
      expect(decoded.floatAt(9), 1.0);
      expect(decoded.bytesAt(3), isNotNull);
      expect(decoded.fields, hasLength(9));
      expect(decoded.isEmpty, isFalse);
    });

    test('answers null for absent and mistyped fields', () {
      final message = ProtoMessage()..setVarint(1, 5);

      expect(message.varintAt(2), isNull);
      expect(message.boolAt(2), isNull);
      expect(message.fixed64At(1), isNull);
      expect(message.floatAt(1), isNull);
      expect(message.bytesAt(1), isNull);
      expect(message.stringAt(1), isNull);
      expect(message.messageAt(1), isNull);
      expect(message.boolWrapperAt(1), isNull);
      expect(message.stringWrapperAt(1), isNull);
      expect(message.intWrapperAt(1), isNull);
      expect(message.floatWrapperAt(1), isNull);
      expect(message.valueAt(9), isNull);
    });

    test('treats an empty wrapper as the zero value', () {
      final message = ProtoMessage()
        ..setMessage(1, ProtoMessage())
        ..setMessage(2, ProtoMessage())
        ..setMessage(3, ProtoMessage())
        ..setMessage(4, ProtoMessage());

      expect(message.boolWrapperAt(1), isFalse);
      expect(message.stringWrapperAt(2), '');
      expect(message.intWrapperAt(3), 0);
      expect(message.floatWrapperAt(4), 0.0);
    });

    test('reads a float wrapper that carries a value', () {
      final message = ProtoMessage()
        ..setMessage(
          1,
          ProtoMessage()..setField(1, const ProtoFixed32(0x40000000)),
        );

      expect(message.floatWrapperAt(1), 2.0);
    });

    test('keeps the last value of a repeated singular field', () {
      final bytes = Uint8List.fromList([0x08, 1, 0x08, 9]);

      expect(ProtoMessage.decode(bytes).varintAt(1), 9);
    });

    test('replaces a field in place and keeps the rest in order', () {
      final message = ProtoMessage.decode(
        Uint8List.fromList([0x08, 1, 0x10, 2, 0x08, 3]),
      )..setVarint(1, 8);

      expect(
        message.fields.map((field) => field.number),
        orderedEquals([1, 2]),
      );
      expect(message.varintAt(1), 8);
      expect(message.varintAt(2), 2);
    });

    test('appends an unseen field and clears on request', () {
      final message = ProtoMessage()..setVarint(4, 1);
      message.addField(const ProtoField(4, ProtoVarint(2)));

      expect(message.fields, hasLength(2));
      message.clearField(4);
      expect(message.isEmpty, isTrue);
      expect(message.encode(), isEmpty);
    });

    test('clones without sharing the field list', () {
      final original = ProtoMessage()..setVarint(1, 1);
      final copy = original.clone()..setVarint(1, 2);

      expect(original.varintAt(1), 1);
      expect(copy.varintAt(1), 2);
    });

    test('keeps fields it does not understand through a round trip', () {
      // Field 4242 is nothing Flucord models; it must survive a decode, an
      // unrelated edit, and the re-encode that a settings write performs.
      final source = ProtoMessage()
        ..setVarint(1, 1)
        ..setString(4242, 'server-only')
        ..setField(4243, const ProtoFixed32(7));

      final edited = ProtoMessage.decode(source.encode())..setVarint(1, 2);
      final result = ProtoMessage.decode(edited.encode());

      expect(result.varintAt(1), 2);
      expect(result.stringAt(4242), 'server-only');
      expect(result.floatAt(4243), isNotNull);
    });

    test('replaces malformed UTF-8 rather than failing the load', () {
      final message = ProtoMessage()
        ..setField(1, ProtoBytes(Uint8List.fromList([0xc3, 0x28])));

      expect(message.stringAt(1), isNotEmpty);
    });
  });
}
