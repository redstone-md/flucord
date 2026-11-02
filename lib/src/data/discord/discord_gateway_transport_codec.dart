import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../zstd/zstd_codec.dart';
import 'discord_gateway_framing.dart';

/// Turns raw socket frames into Gateway payloads.
///
/// Discord layers two independent codecs on one socket: an optional transport
/// compression that spans the whole connection, and the per-payload encoding
/// inside it. Keeping them behind a single object means the Gateway client
/// never has to know whether compression is on, and guarantees the two are
/// reset together — a decompressor that survived a reconnect would try to
/// resolve matches against the previous session's bytes.
final class DiscordGatewayTransportCodec {
  DiscordGatewayTransportCodec({
    required this.framing,
    required this.compression,
  }) : _stream = compression == null ? null : ZstdCodec.stream();

  /// Resolves the codec for a profile's encoding and negotiated compression.
  factory DiscordGatewayTransportCodec.forProfile({
    required String encoding,
    required String? compression,
  }) {
    if (compression != null && compression != zstdStream) {
      throw ArgumentError.value(
        compression,
        'compression',
        'Flucord only decodes the zstd-stream transport compression',
      );
    }
    return DiscordGatewayTransportCodec(
      framing: DiscordGatewayFraming.forEncoding(encoding),
      compression: compression,
    );
  }

  /// The only transport compression Flucord negotiates.
  static const zstdStream = 'zstd-stream';

  /// The largest frame, in characters or bytes, decoded on the calling isolate.
  ///
  /// Decoding this much takes about 2 ms on a desktop, a small part of a 16 ms
  /// frame, and a worker adds about as much delay. A READY is about 700 KB even
  /// on a small account, so it is always above this, and a READY_SUPPLEMENTAL at
  /// about 20 KB is below it.
  static const largeFrameSize = 128 * 1024;

  final DiscordGatewayFraming framing;
  final String? compression;
  final ZstdStreamDecoder? _stream;

  /// Whether outgoing frames must be written as binary WebSocket frames.
  bool get isBinary => framing.isBinary;

  /// Encodes an outgoing payload. Outgoing frames are never compressed.
  Object encode(Map<String, Object?> payload) => framing.encode(payload);

  /// Decodes one socket frame into every payload it carries.
  ///
  /// Without compression a frame is exactly one payload. With
  /// `compress=zstd-stream` a frame is a slice of one continuous stream, and
  /// the server is free to flush several payloads into the same slice or none
  /// at all, so the result is a batch and may legitimately be empty.
  ///
  /// Over [largeFrameSize], the result is a future and the decoding runs on a
  /// worker isolate, where it cannot stop the UI. A frame that is broken throws
  /// the same error either way. Frames must still come here in arrival order,
  /// because the decompression runs here and depends on the frame before.
  FutureOr<List<Map<String, Object?>>> decode(Object? frame) {
    if (frame is DiscordGatewayDecodedJsonFrame) return frame.payloads;
    // A local, so that the closures below do not take this object, with its
    // decompressor, to the worker.
    final framing = this.framing;
    final decompressor = _stream;
    if (decompressor == null) {
      return _inWorkerIfLarge(switch (frame) {
        final String text => text.length,
        final List<int> bytes => bytes.length,
        _ => 0,
      }, () => _decodeWhole(framing, frame));
    }

    final bytes = switch (frame) {
      Uint8List() => frame,
      final List<int> raw => Uint8List.fromList(raw),
      _ => null,
    };
    if (bytes == null) return const [];
    final expanded = decompressor.feed(bytes);
    if (expanded.isEmpty) return const [];
    return _inWorkerIfLarge(
      expanded.length,
      () => framing.decodeBatch(expanded),
    );
  }

  static List<Map<String, Object?>> _decodeWhole(
    DiscordGatewayFraming framing,
    Object? frame,
  ) {
    final payload = framing.decode(frame);
    return payload == null ? const [] : [payload];
  }

  static FutureOr<List<Map<String, Object?>>> _inWorkerIfLarge(
    int size,
    List<Map<String, Object?>> Function() decode,
  ) => size > largeFrameSize
      ? Isolate.run(decode, debugName: 'gateway frame')
      : decode();

  /// Discards stream state so a reconnect starts clean.
  void reset() => _stream?.reset();

  @override
  String toString() =>
      'DiscordGatewayTransportCodec(${framing.encoding}, '
      '${compression ?? 'uncompressed'})';
}
