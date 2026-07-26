import 'dart:convert';
import 'dart:typed_data';

import 'discord_etf_codec.dart';

/// Writes one Discord Gateway term in External Term Format.
///
/// The renderer packs outgoing frames with `erlpack`, which emits binaries for
/// strings, atoms for `null`/`true`/`false`, and proper lists terminated by
/// `NIL_EXT`. Flucord produces the same shapes so identify, resume, heartbeat,
/// voice-state, and bulk guild-subscription frames stay byte-compatible with
/// the observed client.
final class DiscordEtfEncoder {
  DiscordEtfEncoder._();

  static const _maxDepth = 128;
  static const _smallIntegerMax = 255;
  static const _integerMin = -2147483648;
  static const _integerMax = 2147483647;

  static Uint8List encode(Object? value) {
    final encoder = DiscordEtfEncoder._();
    encoder._buffer.addByte(DiscordEtfTag.version);
    encoder._writeTerm(value, 0);
    return encoder._buffer.takeBytes();
  }

  final BytesBuilder _buffer = BytesBuilder(copy: true);

  void _writeTerm(Object? value, int depth) {
    if (depth > _maxDepth) {
      throw DiscordEtfException('ETF value nesting exceeds $_maxDepth');
    }
    switch (value) {
      case null:
        _writeAtom(DiscordEtfAtoms.nil);
      case final bool flag:
        _writeAtom(flag ? DiscordEtfAtoms.true_ : DiscordEtfAtoms.false_);
      case final int number:
        _writeInteger(number);
      case final double number:
        _writeFloat(number);
      case final String text:
        _writeBinary(text);
      case final Iterable<Object?> items:
        _writeList(items, depth);
      case final Map<Object?, Object?> entries:
        _writeMap(entries, depth);
      default:
        throw DiscordEtfException(
          'Cannot encode ${value.runtimeType} as an ETF Gateway term',
        );
    }
  }

  void _writeList(Iterable<Object?> items, int depth) {
    final values = items.toList(growable: false);
    if (values.isEmpty) {
      _buffer.addByte(DiscordEtfTag.nil);
      return;
    }
    _buffer.addByte(DiscordEtfTag.list);
    _writeUint32(values.length);
    for (final item in values) {
      _writeTerm(item, depth + 1);
    }
    _buffer.addByte(DiscordEtfTag.nil);
  }

  void _writeMap(Map<Object?, Object?> entries, int depth) {
    _buffer.addByte(DiscordEtfTag.map);
    _writeUint32(entries.length);
    for (final entry in entries.entries) {
      _writeTerm(entry.key, depth + 1);
      _writeTerm(entry.value, depth + 1);
    }
  }

  void _writeInteger(int value) {
    if (value >= 0 && value <= _smallIntegerMax) {
      _buffer
        ..addByte(DiscordEtfTag.smallInteger)
        ..addByte(value);
      return;
    }
    if (value >= _integerMin && value <= _integerMax) {
      _buffer.addByte(DiscordEtfTag.integer);
      final view = ByteData(4)..setInt32(0, value, Endian.big);
      _buffer.add(view.buffer.asUint8List());
      return;
    }
    _writeBigInteger(value);
  }

  void _writeBigInteger(int value) {
    final negative = value < 0;
    var magnitude = negative ? -BigInt.from(value) : BigInt.from(value);
    final digits = <int>[];
    while (magnitude > BigInt.zero) {
      digits.add((magnitude & BigInt.from(0xff)).toInt());
      magnitude >>= 8;
    }
    _buffer
      ..addByte(DiscordEtfTag.smallBig)
      ..addByte(digits.length)
      ..addByte(negative ? 1 : 0)
      ..add(digits);
  }

  void _writeFloat(double value) {
    if (value.isNaN || value.isInfinite) {
      throw DiscordEtfException('ETF cannot represent the float $value');
    }
    _buffer.addByte(DiscordEtfTag.newFloat);
    final view = ByteData(8)..setFloat64(0, value, Endian.big);
    _buffer.add(view.buffer.asUint8List());
  }

  void _writeBinary(String text) {
    final bytes = utf8.encode(text);
    _buffer.addByte(DiscordEtfTag.binary);
    _writeUint32(bytes.length);
    _buffer.add(bytes);
  }

  void _writeAtom(String atom) {
    final bytes = utf8.encode(atom);
    _buffer
      ..addByte(DiscordEtfTag.smallAtomUtf8)
      ..addByte(bytes.length)
      ..add(bytes);
  }

  void _writeUint32(int value) {
    final view = ByteData(4)..setUint32(0, value, Endian.big);
    _buffer.add(view.buffer.asUint8List());
  }
}
