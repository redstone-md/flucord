import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/data/discord_rpc/discord_rpc_framing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the wire bytes of one frame, the way a client would.
Uint8List _frame(DiscordRpcOpcode opcode, Map<String, Object?> payload) =>
    encodeFrame(opcode, payload);

void main() {
  group('the opcode enum', () {
    test('carries the documented wire values', () {
      expect(DiscordRpcOpcode.handshake.wireValue, 0);
      expect(DiscordRpcOpcode.frame.wireValue, 1);
      expect(DiscordRpcOpcode.close.wireValue, 2);
      expect(DiscordRpcOpcode.ping.wireValue, 3);
      expect(DiscordRpcOpcode.pong.wireValue, 4);
    });

    test('answers null for an opcode this protocol does not carry', () {
      expect(DiscordRpcOpcode.fromWire(9), isNull);
      expect(DiscordRpcOpcode.fromWire(null), isNull);
      expect(DiscordRpcOpcode.fromWire('1'), isNull);
    });
  });

  group('the encoder', () {
    test('writes the header little-endian ahead of the JSON payload', () {
      final payload = {'v': 1, 'client_id': '999999999999999999'};
      final frame = _frame(DiscordRpcOpcode.handshake, payload);

      final header = ByteData.sublistView(frame, 0, 8);
      expect(header.getUint32(0, Endian.little), 0);
      expect(
        header.getUint32(4, Endian.little),
        utf8.encode(jsonEncode(payload)).length,
      );
      expect(
        utf8.decode(frame.sublist(8)),
        '{"v":1,"client_id":"999999999999999999"}',
      );
    });

    test('encodes a payload with a non-ascii character whole', () {
      final frame = _frame(DiscordRpcOpcode.frame, {'cmd': 'PING', 'n': 'é'});

      final header = ByteData.sublistView(frame, 0, 8);
      expect(header.getUint32(4, Endian.little), frame.length - 8);
      expect(utf8.decode(frame.sublist(8)), '{"cmd":"PING","n":"é"}');
    });

    test('encodes an empty payload as just the two-character object', () {
      final frame = _frame(DiscordRpcOpcode.close, {});

      expect(frame.length, 10);
      final header = ByteData.sublistView(frame, 0, 8);
      expect(header.getUint32(0, Endian.little), 2);
      expect(header.getUint32(4, Endian.little), 2);
    });
  });

  group('the decoder', () {
    test('reads one handshake frame whole', () {
      final decoder = DiscordRpcFrameDecoder();
      final frames = decoder.push(
        _frame(DiscordRpcOpcode.handshake, {
          'v': 1,
          'client_id': '999999999999999999',
        }),
      );

      expect(decoder.isPoisoned, isFalse);
      expect(decoder.pending, isEmpty);
      final frame = frames.single;
      expect(frame.opcode, DiscordRpcOpcode.handshake);
      expect(frame.payload['client_id'], '999999999999999999');
    });

    test('reads two frames glued together in one stream', () {
      final decoder = DiscordRpcFrameDecoder();
      final bytes = BytesBuilder();
      bytes.add(_frame(DiscordRpcOpcode.ping, {'nonce': 'a'}));
      bytes.add(_frame(DiscordRpcOpcode.pong, {'nonce': 'a'}));
      final frames = decoder.push(bytes.toBytes());

      expect(frames.map((frame) => frame.opcode), [
        DiscordRpcOpcode.ping,
        DiscordRpcOpcode.pong,
      ]);
    });

    test('reads a frame split across two pushes', () {
      final decoder = DiscordRpcFrameDecoder();
      final whole = _frame(DiscordRpcOpcode.frame, {'cmd': 'PING'});
      final first = decoder.push(whole.sublist(0, 5));
      expect(first, isEmpty);
      expect(decoder.pending, isNotEmpty);

      final frames = decoder.push(whole.sublist(5));
      expect(frames.single.payload['cmd'], 'PING');
      expect(decoder.pending, isEmpty);
    });

    test('reads several frames split at every offset', () {
      final bytes = BytesBuilder();
      bytes.add(_frame(DiscordRpcOpcode.ping, {'nonce': '1'}));
      bytes.add(_frame(DiscordRpcOpcode.frame, {'cmd': 'SET_ACTIVITY'}));
      final whole = bytes.toBytes();

      for (var cut = 0; cut <= whole.length; cut++) {
        final decoder = DiscordRpcFrameDecoder();
        final frames = [
          ...decoder.push(whole.sublist(0, cut)),
          ...decoder.push(whole.sublist(cut)),
        ];
        expect(frames.map((frame) => frame.opcode), [
          DiscordRpcOpcode.ping,
          DiscordRpcOpcode.frame,
        ], reason: 'cut at $cut');
      }
    });

    test('carries every opcode through the round trip', () {
      for (final opcode in DiscordRpcOpcode.values) {
        final decoder = DiscordRpcFrameDecoder();
        final frames = decoder.push(_frame(opcode, {'nonce': 'n'}));
        expect(frames.single.opcode, opcode);
      }
    });

    test('reads a close frame with an empty body', () {
      final decoder = DiscordRpcFrameDecoder();
      final frames = decoder.push(_frame(DiscordRpcOpcode.close, {}));
      expect(frames.single.opcode, DiscordRpcOpcode.close);
      expect(frames.single.payload, isEmpty);
    });

    test('reads a close frame whose body is missing entirely', () {
      final decoder = DiscordRpcFrameDecoder();
      final frame = Uint8List(8);
      ByteData.sublistView(frame, 0, 8)
        ..setUint32(0, 2, Endian.little)
        ..setUint32(4, 0, Endian.little);

      final frames = decoder.push(frame);
      expect(frames.single.opcode, DiscordRpcOpcode.close);
      expect(frames.single.payload, isEmpty);
    });

    test('refuses a body that is not a JSON object', () {
      final decoder = DiscordRpcFrameDecoder();
      final body = utf8.encode('[1,2,3]');
      final frame = Uint8List(8 + body.length);
      ByteData.sublistView(frame, 0, 8)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, body.length, Endian.little);
      frame.setAll(8, body);

      final frames = decoder.push(frame);
      expect(frames, isEmpty);
      expect(decoder.isPoisoned, isTrue);
    });

    test('refuses a body that is not valid UTF-8', () {
      final decoder = DiscordRpcFrameDecoder();
      final body = Uint8List.fromList([0xff, 0xfe, 0xff]);
      final frame = Uint8List(8 + body.length);
      ByteData.sublistView(frame, 0, 8)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, body.length, Endian.little);
      frame.setAll(8, body);

      decoder.push(frame);
      expect(decoder.isPoisoned, isTrue);
    });

    test('refuses an opcode this protocol does not carry', () {
      final decoder = DiscordRpcFrameDecoder();
      final frame = Uint8List(8)..setAll(0, [7, 0, 0, 0, 0, 0, 0, 0]);

      decoder.push(frame);
      expect(decoder.isPoisoned, isTrue);
    });

    test('refuses a payload longer than the server accepts', () {
      final decoder = DiscordRpcFrameDecoder();
      final frame = Uint8List(8);
      ByteData.sublistView(frame, 0, 8)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(
          4,
          DiscordRpcFrameDecoder.maxPayloadBytes + 1,
          Endian.little,
        );

      decoder.push(frame);
      expect(decoder.isPoisoned, isTrue);
    });

    test('refuses an empty body on any opcode but close', () {
      final decoder = DiscordRpcFrameDecoder();
      final frame = Uint8List(8);
      ByteData.sublistView(frame, 0, 8)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 0, Endian.little);

      decoder.push(frame);
      expect(decoder.isPoisoned, isTrue);
    });

    test('a poisoned decoder answers nothing further', () {
      final decoder = DiscordRpcFrameDecoder();
      decoder.push(Uint8List.fromList([9, 0, 0, 0, 0, 0, 0, 0]));
      expect(decoder.isPoisoned, isTrue);

      expect(
        decoder.push(_frame(DiscordRpcOpcode.ping, {'nonce': 'a'})),
        isEmpty,
      );
      expect(decoder.pending, isEmpty);
    });

    test('cuts a connection that buffers without finishing a frame', () {
      final decoder = DiscordRpcFrameDecoder();
      final oversized = Uint8List.fromList(
        List.filled(DiscordRpcFrameDecoder.maxBufferedBytes + 1, 0x7b),
      );
      decoder.push(oversized);
      expect(decoder.isPoisoned, isTrue);
    });

    test('reset lets a decoder be reused after a poison', () {
      final decoder = DiscordRpcFrameDecoder();
      decoder.push(Uint8List.fromList([9, 0, 0, 0, 0, 0, 0, 0]));
      expect(decoder.isPoisoned, isTrue);

      decoder.reset();
      expect(decoder.isPoisoned, isFalse);
      final frames = decoder.push(
        _frame(DiscordRpcOpcode.ping, {'nonce': 'a'}),
      );
      expect(frames.single.opcode, DiscordRpcOpcode.ping);
    });

    test('carries nothing when fed nothing', () {
      final decoder = DiscordRpcFrameDecoder();
      expect(decoder.push(Uint8List(0)), isEmpty);
      expect(decoder.pending, isEmpty);
    });

    test('round trips a frame through encode and decode', () {
      final payload = {
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': 9999,
          'activity': {'state': 'In a Group'},
        },
        'nonce': '647d814a-4cf8-4fbb-948f-898abd24f55b',
      };
      final decoder = DiscordRpcFrameDecoder();
      final frame = decoder
          .push(_frame(DiscordRpcOpcode.frame, payload))
          .single;

      expect(frame.opcode, DiscordRpcOpcode.frame);
      expect(frame.payload, equals(payload));
    });

    test('an encoded frame re-encodes to itself', () {
      final original = _frame(DiscordRpcOpcode.frame, {'cmd': 'PING'});
      final decoder = DiscordRpcFrameDecoder();
      final frame = decoder.push(original).single;
      expect(frame.encode(), original);
    });
  });
}
