import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_etf_codec.dart';
import 'package:flucord/src/data/discord/discord_gateway_framing.dart';
import 'package:flucord/src/data/discord/discord_gateway_transport_codec.dart';
import 'package:flucord/src/data/zstd/zstd_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the installed profile connects without transport compression', () {
    const profile = DiscordDesktopProtocolProfile.installedStable20260725;

    // The decoder is in place and covered, but zstd-stream stays off until it
    // has been proven against a real authenticated session. It shipped enabled
    // in 0.0.2 and broke workspace loading, because a compressed frame can
    // carry several payloads and the reader only accepted one.
    expect(profile.negotiatedCompression, isNull);
    expect(
      profile.connectionUri().toString(),
      'wss://gateway.discord.gg?encoding=etf&v=9',
    );
    expect(
      profile.gatewayUri().toString(),
      'wss://gateway.discord.gg?encoding=etf&v=9&compress=zstd-stream',
    );
  });

  test('resolves an uncompressed codec', () {
    final codec = DiscordGatewayTransportCodec.forProfile(
      encoding: 'etf',
      compression: null,
    );

    expect(codec.isBinary, isTrue);
    expect(codec.compression, isNull);
    expect(codec.toString(), contains('uncompressed'));
    expect(codec.decode(DiscordEtfCodec.encode(const {'op': 11})), [
      const {'op': 11},
    ]);
  });

  test('rejects a compression it cannot decode', () {
    expect(
      () => DiscordGatewayTransportCodec.forProfile(
        encoding: 'etf',
        compression: 'zlib-stream',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('decodes zstd-stream frames flushed per dispatch', () {
    final codec = DiscordGatewayTransportCodec.forProfile(
      encoding: 'etf',
      compression: 'zstd-stream',
    );
    final payloads = [
      const {
        'op': 10,
        'd': <String, Object?>{'heartbeat_interval': 41250},
      },
      const {'op': 0, 's': 1, 't': 'READY', 'd': <String, Object?>{}},
      const {'op': 11, 'd': null},
    ];
    final chunks = _compressPerMessage(
      payloads.map(DiscordEtfCodec.encode).toList(growable: false),
    );

    final decoded = chunks.expand(codec.decode).toList(growable: false);

    expect(decoded, payloads);
    expect(codec.isBinary, isTrue);
    expect(codec.toString(), contains('zstd-stream'));
  });

  test('a partial frame produces no payload', () {
    final codec = DiscordGatewayTransportCodec.forProfile(
      encoding: 'etf',
      compression: 'zstd-stream',
    );
    final chunk = _compressPerMessage([
      DiscordEtfCodec.encode(const {'op': 11}),
    ]).single;

    expect(codec.decode(Uint8List.sublistView(chunk, 0, 4)), isEmpty);
    expect(codec.decode(Uint8List.sublistView(chunk, 4)), [
      const {'op': 11},
    ]);
    expect(codec.decode('not a binary frame'), isEmpty);
  });

  test('reset discards stream history between connections', () {
    final codec = DiscordGatewayTransportCodec.forProfile(
      encoding: 'etf',
      compression: 'zstd-stream',
    );
    final chunk = _compressPerMessage([
      DiscordEtfCodec.encode(const {'op': 11}),
    ]).single;

    codec.decode(Uint8List.sublistView(chunk, 0, 4));
    codec.reset();

    expect(codec.decode(chunk), [
      const {'op': 11},
    ]);
  });

  test('one compressed frame may carry several payloads', () {
    // Regression: the decoder used to demand exactly one term per frame and
    // threw "trailing bytes" on a batch, discarding the whole frame. When that
    // frame held READY, the workspace never loaded and the client reported
    // Discord as unreachable.
    final codec = DiscordGatewayTransportCodec.forProfile(
      encoding: 'etf',
      compression: 'zstd-stream',
    );
    const batch = [
      {
        'op': 10,
        'd': <String, Object?>{'heartbeat_interval': 41250},
      },
      {'op': 0, 's': 1, 't': 'READY', 'd': <String, Object?>{}},
      {'op': 0, 's': 2, 't': 'READY_SUPPLEMENTAL', 'd': <String, Object?>{}},
    ];
    final packed = BytesBuilder(copy: false);
    for (final payload in batch) {
      packed.add(DiscordEtfCodec.encode(payload));
    }
    final frame = _compressPerMessage([packed.takeBytes()]).single;

    expect(codec.decode(frame), batch);
  });

  test('outgoing frames stay uncompressed', () {
    final codec = DiscordGatewayTransportCodec.forProfile(
      encoding: 'etf',
      compression: 'zstd-stream',
    );

    final encoded = codec.encode(const {'op': 1, 'd': null});

    expect(DiscordEtfCodec.decode(encoded as Uint8List), const {
      'op': 1,
      'd': null,
    });
    expect(codec.framing, isA<DiscordGatewayEtfFraming>());
  });
}

/// Compresses each payload into its own flushed slice of one zstd stream.
///
/// This is the shape Discord produces: a single frame spanning the connection
/// with a flush after every dispatch, so each WebSocket message decompresses to
/// exactly one payload while still back-referencing earlier ones.
List<Uint8List> _compressPerMessage(List<Uint8List> payloads) {
  // Building a real zstd stream without a compressor: emit one raw block per
  // payload inside a single frame. A raw block is a legal flush boundary and
  // keeps the fixture independent of any encoder.
  final chunks = <Uint8List>[];
  final header = BytesBuilder(copy: false)
    ..add(const [0x28, 0xb5, 0x2f, 0xfd])
    ..addByte(0x00)
    ..addByte((17 - 10) << 3);
  var first = true;
  for (var index = 0; index < payloads.length; index++) {
    final payload = payloads[index];
    final last = index == payloads.length - 1;
    final descriptor = (payload.length << 3) | (last ? 1 : 0);
    final chunk = BytesBuilder(copy: false);
    if (first) {
      chunk.add(header.takeBytes());
      first = false;
    }
    chunk
      ..addByte(descriptor & 0xff)
      ..addByte((descriptor >> 8) & 0xff)
      ..addByte((descriptor >> 16) & 0xff)
      ..add(payload);
    chunks.add(chunk.takeBytes());
  }
  // Sanity: the concatenation must be one decodable frame.
  final joined = BytesBuilder(copy: false);
  for (final chunk in chunks) {
    joined.add(chunk);
  }
  final all = joined.takeBytes();
  final expected = BytesBuilder(copy: false);
  for (final payload in payloads) {
    expected.add(payload);
  }
  assert(
    ZstdCodec.decode(all).length == expected.takeBytes().length,
    'fixture frame must decode',
  );
  return chunks;
}
