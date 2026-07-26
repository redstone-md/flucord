import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flucord/src/data/zstd/zstd_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Streaming and rejection coverage against libzstd 1.5.7.
///
/// The one-shot corpus in `zstd_reference_test.dart` is dominated by frames
/// that declare their content size, so they never exercise the window
/// descriptor, unknown content length, or window wrap-around. Discord's
/// Gateway uses exactly those, and a decoder that only handles single-segment
/// frames would still pass the first corpus.
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

  // The streaming corpus forces the window-descriptor path; the RLE corpus is
  // hand-built because libzstd never emits an RLE block for these inputs, so a
  // decoder that mis-frames one would otherwise pass everything.
  final streamed = [
    ...load('manifest-stream.json'),
    ...load('manifest-rle.json'),
  ];
  final rejected = load('manifest-negative.json');

  for (final entry in streamed) {
    final name = entry['name']! as String;
    final note = entry['note']! as String;

    test('one-shot decode of $name — $note', () async {
      final compressed = File('$fixtures/$name.zst').readAsBytesSync();

      final decoded = ZstdCodec.decode(compressed);

      expect(decoded.length, entry['rawBytes']);
      expect(await digestOf(decoded), entry['rawSha256']);
    });

    test('chunked decode of $name matches one-shot', () async {
      final compressed = File('$fixtures/$name.zst').readAsBytesSync();
      final random = Random(0x515D);
      final decoder = ZstdCodec.stream();
      final output = BytesBuilder(copy: false);

      var offset = 0;
      while (offset < compressed.length) {
        final size = min(1 + random.nextInt(2048), compressed.length - offset);
        output.add(
          decoder.feed(
            Uint8List.sublistView(compressed, offset, offset + size),
          ),
        );
        offset += size;
      }

      final decoded = output.takeBytes();
      expect(decoded.length, entry['rawBytes']);
      expect(await digestOf(decoded), entry['rawSha256']);
    });
  }

  for (final entry in rejected) {
    final name = entry['name']! as String;
    final note = entry['note']! as String;

    test('rejects $name — $note', () {
      final compressed = File('$fixtures/$name.zst').readAsBytesSync();

      expect(
        () => ZstdCodec.decode(compressed),
        throwsA(isA<ZstdException>()),
        reason: '$name must be rejected, not silently accepted',
      );
    });

    test('stream rejects $name — $note', () {
      final compressed = File('$fixtures/$name.zst').readAsBytesSync();
      final decoder = ZstdCodec.stream();

      expect(() {
        for (var offset = 0; offset < compressed.length; offset += 64) {
          decoder.feed(
            Uint8List.sublistView(
              compressed,
              offset,
              min(offset + 64, compressed.length),
            ),
          );
        }
        decoder.finish();
      }, throwsA(isA<ZstdException>()));
    });
  }

  test('a block storm cannot make window compaction quadratic', () {
    // 12 KB of frame expands to 4.3 MB across 3,033 blocks. Compacting the
    // window on every block once it is full turned this into minutes of
    // copying, which a Gateway peer could trigger at will.
    final compressed = File(
      '$fixtures/rle-block-window-storm.zst',
    ).readAsBytesSync();
    final entry = streamed.firstWhere(
      (item) => item['name'] == 'rle-block-window-storm',
    );

    final watch = Stopwatch()..start();
    final decoded = ZstdCodec.decode(compressed);
    watch.stop();

    expect(decoded.length, entry['rawBytes']);
    expect(watch.elapsedMilliseconds, lessThan(5000));
  });

  test('reset clears history between sessions', () async {
    final compressed = File('$fixtures/stream-l6.zst').readAsBytesSync();
    final entry = streamed.firstWhere((item) => item['name'] == 'stream-l6');
    final decoder = ZstdCodec.stream();

    decoder.feed(Uint8List.sublistView(compressed, 0, compressed.length ~/ 2));
    decoder.reset();
    final decoded = decoder.feed(compressed);

    expect(decoded.length, entry['rawBytes']);
    expect(await digestOf(decoded), entry['rawSha256']);
  });
}
