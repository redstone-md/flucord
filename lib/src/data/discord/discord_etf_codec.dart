import 'dart:typed_data';

import 'discord_etf_decoder.dart';
import 'discord_etf_encoder.dart';

/// External Term Format tags observed in Discord's `encoding=etf` Gateway.
///
/// The installed renderer packs and unpacks Gateway frames with `erlpack`
/// (native) or its WebAssembly `wetf` fallback. Both cover the same subset of
/// Erlang's term format, so Flucord implements exactly that subset instead of
/// a general-purpose BEAM term reader.
abstract final class DiscordEtfTag {
  static const version = 131;
  static const compressed = 80;
  static const newFloat = 70;
  static const bitBinary = 77;
  static const smallInteger = 97;
  static const integer = 98;
  static const float = 99;
  static const atom = 100;
  static const smallTuple = 104;
  static const largeTuple = 105;
  static const nil = 106;
  static const string = 107;
  static const list = 108;
  static const binary = 109;
  static const smallBig = 110;
  static const largeBig = 111;
  static const smallAtom = 115;
  static const map = 116;
  static const atomUtf8 = 118;
  static const smallAtomUtf8 = 119;
}

/// Raised when a payload is not a term Discord's Gateway encoding can produce.
///
/// It extends [FormatException] so transport code can keep one decoding
/// failure path for both the JSON and the ETF Gateway encodings.
final class DiscordEtfException extends FormatException {
  const DiscordEtfException(super.message, [super.source, super.offset]);

  @override
  String toString() => 'DiscordEtfException: $message (offset $offset)';
}

/// Binds Discord's atom table to Dart values.
///
/// The renderer configures its parser with
/// `atomTable:{nil:null,null:null,true:!0,false:!1}`; every other atom stays a
/// string. Flucord mirrors that table so dispatch payloads decode to the same
/// shapes the JSON encoding produces.
abstract final class DiscordEtfAtoms {
  static const nil = 'nil';
  static const null_ = 'null';
  static const true_ = 'true';
  static const false_ = 'false';

  static Object? resolve(String atom) => switch (atom) {
    nil || null_ => null,
    true_ => true,
    false_ => false,
    _ => atom,
  };
}

/// Encodes and decodes Discord Gateway frames in External Term Format.
abstract final class DiscordEtfCodec {
  /// Decodes one complete versioned term.
  ///
  /// Throws [DiscordEtfException] for truncated buffers, unsupported tags, and
  /// trailing bytes after the term.
  static Object? decode(Uint8List bytes) => DiscordEtfDecoder.decode(bytes);

  /// Encodes one versioned term from Dart's JSON-compatible value graph.
  static Uint8List encode(Object? value) => DiscordEtfEncoder.encode(value);
}
