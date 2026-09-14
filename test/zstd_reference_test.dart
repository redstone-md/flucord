import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flucord/src/data/zstd/zstd_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Differential coverage against libzstd 1.5.7.
///
/// `tool/generate_zstd_vectors.py` compresses known plaintexts with the
/// reference implementation and records each plaintext's length and SHA-256.
/// Flucord's decoder has to reproduce them exactly, so a table-construction or
/// bitstream bug cannot pass unnoticed.
void main() {
  final fixtures = Directory('test/fixtures/zstd');

  Future<String> digestOf(List<int> bytes) async {
    final sink = Sha256().newHashSink();
    sink.add(bytes);
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  final manifest =
      (jsonDecode(File('${fixtures.path}/manifest.json').readAsStringSync())
              as List<Object?>)
          .cast<Map<String, Object?>>();

  test('the reference corpus is present', () {
    expect(manifest, isNotEmpty);
    expect(manifest.length, greaterThanOrEqualTo(20));
  });

  for (final entry in manifest) {
    final name = entry['name']! as String;
    final note = entry['note']! as String;
    final rawBytes = entry['rawBytes']! as int;
    final rawSha256 = entry['rawSha256']! as String;

    test('decodes $name — $note', () async {
      final compressed = File('${fixtures.path}/$name.zst').readAsBytesSync();

      final decoded = ZstdCodec.decode(compressed);

      expect(decoded.length, rawBytes, reason: 'decoded length for $name');
      expect(await digestOf(decoded), rawSha256, reason: 'content of $name');

      if (entry['hasRawFile'] == true) {
        final raw = File('${fixtures.path}/$name.raw').readAsBytesSync();
        expect(decoded, orderedEquals(raw));
      }
    });
  }

  test('streams a frame that is flushed per message', () async {
    final compressed = File(
      '${fixtures.path}/stream-flushed.zst',
    ).readAsBytesSync();
    final sizes =
        (jsonDecode(
                  File(
                    '${fixtures.path}/stream-flushed.chunks.json',
                  ).readAsStringSync(),
                )
                as List<Object?>)
            .cast<int>();
    final expected = File(
      '${fixtures.path}/stream-flushed.raw',
    ).readAsBytesSync();

    final decoder = ZstdCodec.stream();
    final output = BytesBuilder(copy: false);
    var offset = 0;
    final perChunk = <int>[];
    for (final size in sizes) {
      final chunk = Uint8List.sublistView(compressed, offset, offset + size);
      offset += size;
      final produced = decoder.feed(chunk);
      perChunk.add(produced.length);
      output.add(produced);
    }

    expect(offset, compressed.length);
    expect(output.takeBytes(), orderedEquals(expected));
    // Every flushed chunk but the terminating one must yield its own payload,
    // which is exactly what the Gateway relies on to frame dispatches.
    expect(perChunk.take(sizes.length - 1).every((count) => count > 0), isTrue);
  });

  test('a stream decoder survives byte-at-a-time delivery', () {
    final compressed = File(
      '${fixtures.path}/stream-flushed.zst',
    ).readAsBytesSync();
    final expected = File(
      '${fixtures.path}/stream-flushed.raw',
    ).readAsBytesSync();

    final decoder = ZstdCodec.stream();
    final output = BytesBuilder(copy: false);
    for (final byte in compressed) {
      output.add(decoder.feed([byte]));
    }

    expect(output.takeBytes(), orderedEquals(expected));
  });

  test('rejects malformed frames', () {
    expect(
      () => ZstdCodec.decode(Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsA(isA<ZstdException>()),
    );
    expect(
      () => ZstdCodec.decode(Uint8List.fromList([0x28, 0xb5, 0x2f, 0xfd])),
      throwsA(isA<ZstdException>()),
    );
  });

  test('rejects a window larger than the configured ceiling', () {
    final compressed = File(
      '${fixtures.path}/text-multiblock.zst',
    ).readAsBytesSync();

    expect(
      () => ZstdCodec.decode(compressed, maxWindowLog: 10),
      throwsA(isA<ZstdException>()),
    );
  });
}
