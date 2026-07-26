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
}
