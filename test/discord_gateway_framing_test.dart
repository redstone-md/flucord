import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_etf_codec.dart';
import 'package:flucord/src/data/discord/discord_gateway_framing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves the encodings Discord serves', () {
    expect(
      DiscordGatewayFraming.forEncoding('json'),
      isA<DiscordGatewayJsonFraming>(),
    );
    expect(
      DiscordGatewayFraming.forEncoding('etf'),
      isA<DiscordGatewayEtfFraming>(),
    );
    expect(
      () => DiscordGatewayFraming.forEncoding('msgpack'),
      throwsA(isA<ArgumentError>()),
    );
  });

  group('JSON framing', () {
    const framing = DiscordGatewayJsonFraming();

    test('writes text frames', () {
      expect(framing.encoding, 'json');
      expect(framing.isBinary, isFalse);
      expect(framing.encode(const {'op': 1}), '{"op":1}');
      expect(framing.measure(const ['guild', <String, Object?>{}]), 12);
    });

    test('reads payload objects and ignores other frames', () {
      expect(framing.decode('{"op":11}'), const {'op': 11});
      expect(framing.decode('[1]'), isNull);
      expect(framing.decode(Uint8List(0)), isNull);
      expect(framing.decode(null), isNull);
      expect(() => framing.decode('{'), throwsFormatException);
    });
  });

  group('ETF framing', () {
    const framing = DiscordGatewayEtfFraming();

    test('writes binary frames', () {
      expect(framing.encoding, 'etf');
      expect(framing.isBinary, isTrue);

      final encoded = framing.encode(const {'op': 1});

      expect(encoded, isA<Uint8List>());
      expect(DiscordEtfCodec.decode(encoded as Uint8List), const {'op': 1});
    });

    test('measures encoded subscription entries', () {
      expect(
        framing.measure(const ['guild', <String, Object?>{}]),
        DiscordEtfCodec.encode(const ['guild', <String, Object?>{}]).length,
      );
    });

    test('reads typed and untyped byte frames', () {
      final term = DiscordEtfCodec.encode(const {'op': 11});

      expect(framing.decode(term), const {'op': 11});
      expect(framing.decode(term.toList(growable: true)), const {'op': 11});
    });

    test('ignores frames that are not payload objects', () {
      expect(framing.decode('{"op":11}'), isNull);
      expect(framing.decode(null), isNull);
      expect(framing.decode(DiscordEtfCodec.encode(const [1])), isNull);
    });

    test('surfaces malformed terms as format exceptions', () {
      expect(
        () => framing.decode(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  test('both encodings carry the same Gateway payload', () {
    const payload = <String, Object?>{
      'op': 0,
      's': 12,
      't': 'MESSAGE_CREATE',
      'd': {
        'id': '123456789012345678',
        'content': 'héllo 🌍',
        'pinned': false,
        'edited_timestamp': null,
        'mentions': <Object?>[],
        'attachments': [
          {'size': 2048, 'width': 1.5},
        ],
      },
    };

    const json = DiscordGatewayJsonFraming();
    const etf = DiscordGatewayEtfFraming();

    expect(etf.decode(etf.encode(payload)), payload);
    expect(json.decode(json.encode(payload) as String), payload);
    expect(
      etf.decode(etf.encode(payload)),
      jsonDecode(json.encode(payload) as String),
    );
  });
}
