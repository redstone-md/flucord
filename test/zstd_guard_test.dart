import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flucord/src/data/zstd/zstd_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// One frame per malformed-input guard in `lib/src/data/zstd`.
///
/// The conformance corpora only hold frames libzstd chose to emit, so none of
/// them carries a bad FSE accuracy log, an oversized Huffman weight, or a match
/// that reaches before the start of the frame. `tool/generate_zstd_guard_vectors.py`
/// builds those field by field, and each one records the message its guard must
/// produce: asserting only that *something* was thrown would let a fixture drift
/// onto a different check — usually an earlier bounds test — and still pass.
void main() {
  const fixtures = 'test/fixtures/zstd';

  Future<String> digestOf(List<int> bytes) async {
    final sink = Sha256().newHashSink();
    sink.add(bytes);
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  List<Map<String, Object?>> load(String name) =>
      (jsonDecode(File('$fixtures/$name').readAsStringSync()) as List<Object?>)
          .cast<Map<String, Object?>>();

  final legal = load('manifest-guard.json');
  final rejected = load('manifest-guard-reject.json');

  Matcher failsWith(String expected) => throwsA(
    isA<ZstdException>().having(
      (error) => error.toString(),
      'message',
      contains(expected),
    ),
  );

  test('the guard corpus covers every hand-built frame', () {
    expect(legal.length, greaterThanOrEqualTo(5));
    expect(rejected.length, greaterThanOrEqualTo(45));
    // Two fixtures trip the same check from different call sites, so the
    // messages repeat; the names must not.
    expect(
      rejected.map((entry) => entry['name']).toSet().length,
      rejected.length,
    );
  });

  for (final entry in legal) {
    final name = entry['name']! as String;
    final note = entry['note']! as String;

    test('decodes $name — $note', () async {
      final compressed = File('$fixtures/$name.zst').readAsBytesSync();

      final decoded = ZstdCodec.decode(compressed);

      expect(decoded.length, entry['rawBytes'], reason: 'length of $name');
      expect(await digestOf(decoded), entry['rawSha256'], reason: name);
      if (entry['hasRawFile'] == true) {
        expect(
          decoded,
          orderedEquals(File('$fixtures/$name.raw').readAsBytesSync()),
        );
      }
    });

    test('chunked decode of $name matches one-shot', () async {
      final compressed = File('$fixtures/$name.zst').readAsBytesSync();
      final random = Random(0x2B1D);
      final decoder = ZstdCodec.stream();
      final output = BytesBuilder(copy: false);

      var offset = 0;
      while (offset < compressed.length) {
        final size = min(1 + random.nextInt(37), compressed.length - offset);
        output.add(
          decoder.feed(
            Uint8List.sublistView(compressed, offset, offset + size),
          ),
        );
        offset += size;
      }
      decoder.finish();

      final decoded = output.takeBytes();
      expect(decoded.length, entry['rawBytes']);
      expect(await digestOf(decoded), entry['rawSha256']);
    });
  }

  for (final entry in rejected) {
    final name = entry['name']! as String;
    final note = entry['note']! as String;
    final expected = entry['expect']! as String;
    final streamExpected = entry['streamExpect']! as String;

    test('rejects $name — $note', () {
      final compressed = File('$fixtures/$name.zst').readAsBytesSync();

      expect(() => ZstdCodec.decode(compressed), failsWith(expected));
    });

    test('stream rejects $name — $note', () {
      final compressed = File('$fixtures/$name.zst').readAsBytesSync();
      final decoder = ZstdCodec.stream();

      expect(() {
        for (var offset = 0; offset < compressed.length; offset += 7) {
          decoder.feed(
            Uint8List.sublistView(
              compressed,
              offset,
              min(offset + 7, compressed.length),
            ),
          );
        }
        // Truncation is only an error once the producer stops sending, so the
        // cut-short fixtures surface here rather than during feed().
        decoder.finish();
      }, failsWith(streamExpected));
    });
  }

  test('a skippable frame is stepped over by the incremental decoder', () {
    // The one-shot corpus already covers skippable frames; feeding one in
    // pieces is what exercises the decoder's separate skip-ahead state.
    final compressed = File('$fixtures/skippable-frame.zst').readAsBytesSync();
    final expected = File('$fixtures/skippable-frame.raw').readAsBytesSync();
    final decoder = ZstdCodec.stream();
    final output = BytesBuilder(copy: false);

    for (var offset = 0; offset < compressed.length; offset += 100) {
      output.add(
        decoder.feed(
          Uint8List.sublistView(
            compressed,
            offset,
            min(offset + 100, compressed.length),
          ),
        ),
      );
    }
    decoder.finish();

    expect(output.takeBytes(), orderedEquals(expected));
  });

  test('the exception carries the offset the decoder stopped at', () {
    // Transport code logs this string, so its shape is part of the contract.
    expect(
      const ZstdException('Block header is truncated', null, 42).toString(),
      'ZstdException: Block header is truncated (offset 42)',
    );
  });
}
