import 'dart:convert';
import 'dart:typed_data';

import 'discord_etf_codec.dart';

/// One Gateway wire encoding.
///
/// Discord advertises `encoding` as a query parameter and then frames every
/// payload with it in both directions. Keeping the encoding behind this
/// contract lets the desktop Gateway client stay identical for JSON and ETF
/// while the socket decides between text and binary frames.
abstract interface class DiscordGatewayFraming {
  /// Value sent as the `encoding` query parameter.
  String get encoding;

  /// Whether encoded frames must be written as binary WebSocket frames.
  bool get isBinary;

  /// Encodes an outgoing payload into a `String` or a [Uint8List].
  Object encode(Map<String, Object?> payload);

  /// Encoded byte length of an arbitrary term.
  ///
  /// Discord's bulk guild-subscription batching counts encoded bytes, so the
  /// budget has to be measured with the encoding the socket actually uses.
  int measure(Object? term);

  /// Decodes an incoming frame, or returns `null` when it is not a payload
  /// object this encoding can produce.
  ///
  /// Throws [FormatException] when the frame is structurally invalid.
  Map<String, Object?>? decode(Object? frame);

  /// Decodes every payload packed into one already-decompressed buffer.
  ///
  /// Transport compression can put several payloads in one frame, so the
  /// batch has to be read out rather than rejected as trailing bytes.
  List<Map<String, Object?>> decodeBatch(Uint8List bytes);

  /// Resolves the framing for an `encoding` query value.
  static DiscordGatewayFraming forEncoding(String encoding) =>
      switch (encoding) {
        'json' => const DiscordGatewayJsonFraming(),
        'etf' => const DiscordGatewayEtfFraming(),
        _ => throw ArgumentError.value(
          encoding,
          'encoding',
          'Discord only serves json and etf Gateway encodings',
        ),
      };
}

/// Text framing used by Discord's documented Gateway encoding.
final class DiscordGatewayJsonFraming implements DiscordGatewayFraming {
  const DiscordGatewayJsonFraming();

  @override
  String get encoding => 'json';

  @override
  bool get isBinary => false;

  @override
  Object encode(Map<String, Object?> payload) => jsonEncode(payload);

  @override
  int measure(Object? term) => utf8.encode(jsonEncode(term)).length;

  @override
  Map<String, Object?>? decode(Object? frame) {
    if (frame is! String) return null;
    final decoded = jsonDecode(frame);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  }

  @override
  List<Map<String, Object?>> decodeBatch(Uint8List bytes) {
    final payload = decode(utf8.decode(bytes));
    return payload == null ? const [] : [payload];
  }
}

/// A JSON text frame that a socket's worker isolate has already decoded.
///
/// It crosses to the main isolate in this form, so that isolate does no JSON
/// work. A broken frame keeps its error, which [payloads] throws on the main
/// isolate, so it fails there just as a text frame does.
final class DiscordGatewayDecodedJsonFrame {
  const DiscordGatewayDecodedJsonFrame._(this._payload, this._failure);

  factory DiscordGatewayDecodedJsonFrame.read(String text) {
    try {
      final payload = const DiscordGatewayJsonFraming().decode(text);
      return DiscordGatewayDecodedJsonFrame._(payload, null);
    } on FormatException catch (failure) {
      return DiscordGatewayDecodedJsonFrame._(null, failure);
    }
  }

  final Map<String, Object?>? _payload;
  final FormatException? _failure;

  /// The frame's payload, as [DiscordGatewayFraming.decode] gives it.
  List<Map<String, Object?>> get payloads {
    final failure = _failure;
    if (failure != null) throw failure;
    final payload = _payload;
    return payload == null ? const [] : [payload];
  }
}

/// Binary framing used by the installed desktop client.
final class DiscordGatewayEtfFraming implements DiscordGatewayFraming {
  const DiscordGatewayEtfFraming();

  @override
  String get encoding => 'etf';

  @override
  bool get isBinary => true;

  @override
  Object encode(Map<String, Object?> payload) =>
      DiscordEtfCodec.encode(payload);

  @override
  int measure(Object? term) => DiscordEtfCodec.encode(term).length;

  @override
  Map<String, Object?>? decode(Object? frame) {
    final bytes = switch (frame) {
      Uint8List() => frame,
      final List<int> raw => Uint8List.fromList(raw),
      _ => null,
    };
    if (bytes == null) return null;
    final decoded = DiscordEtfCodec.decode(bytes);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  @override
  List<Map<String, Object?>> decodeBatch(Uint8List bytes) =>
      DiscordEtfCodec.decodeAll(
        bytes,
      ).whereType<Map<String, Object?>>().toList(growable: false);
}
