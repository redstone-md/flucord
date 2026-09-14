import 'dart:convert';
import 'dart:typed_data';

/// One frame of the Discord local RPC protocol.
///
/// Framing is a 4-byte little-endian opcode, a 4-byte little-endian payload
/// length, then the JSON payload as UTF-8. Source:
/// https://github.com/discord/discord-api-docs/blob/main/developers/topics/rpc.mdx
/// (RPC over IPC).
enum DiscordRpcOpcode {
  handshake(0),
  frame(1),
  close(2),
  ping(3),
  pong(4);

  const DiscordRpcOpcode(this.wireValue);

  final int wireValue;

  static DiscordRpcOpcode? fromWire(Object? value) => switch (value) {
    0 => handshake,
    1 => frame,
    2 => close,
    3 => ping,
    4 => pong,
    _ => null,
  };
}

/// The protocol version this server speaks. Version 1 is the only one.
const int discordRpcVersion = 1;

/// One decoded frame: the opcode and the payload as parsed JSON.
final class DiscordRpcFrame {
  const DiscordRpcFrame({required this.opcode, required this.payload});

  final DiscordRpcOpcode opcode;

  /// The JSON payload, as the protocol sends one. A PING carries `{"v": 1}`;
  /// a HANDSHAKE carries `{"v": 1, "client_id": ...}`; a FRAME carries the
  /// command object.
  final Map<String, Object?> payload;

  Uint8List encode() => encodeFrame(opcode, payload);
}

/// Encodes one frame into a single buffer.
///
/// The wire rule is that a frame goes out in one write: a pipe reader that
/// sees the header without the payload drops the connection.
Uint8List encodeFrame(DiscordRpcOpcode opcode, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final frame = Uint8List(8 + body.length);
  ByteData.sublistView(frame, 0, 8)
    ..setUint32(0, opcode.wireValue, Endian.little)
    ..setUint32(4, body.length, Endian.little);
  frame.setAll(8, body);
  return frame;
}

/// Decodes the frames in a byte stream, answering what is left over.
///
/// A stream delivers frames glued together and split apart in any shape, so
/// the decoder keeps whatever it cannot parse yet and the caller feeds the
/// next chunk in later. A frame whose declared length is not a sane JSON
/// object size poisons the stream: there is no way to know where it really
/// ends, so the rest is refused until the caller resets the decoder.
final class DiscordRpcFrameDecoder {
  /// The largest payload this server accepts. A real frame is a few kilobytes
  /// of JSON; anything larger is a broken pipe speaking, not a client.
  static const int maxPayloadBytes = 1 << 20;

  /// The longest prefix of unconsumed bytes this decoder holds. A client that
  /// keeps a stream alive without ever finishing a frame is cut here rather
  /// than growing without bound.
  static const int maxBufferedBytes = maxPayloadBytes + 8;
  Uint8List _buffer = Uint8List(0);
  bool _poisoned = false;

  /// Whether the decoder is holding a frame it cannot make sense of. A
  /// poisoned decoder answers nothing further; the connection is closed.
  bool get isPoisoned => _poisoned;

  /// Bytes read but not yet parsed into a frame.
  Uint8List get pending => _buffer;

  /// Feeds bytes in and answers every complete frame they completed.
  List<DiscordRpcFrame> push(Uint8List bytes) {
    if (_poisoned) return const [];
    if (_buffer.length + bytes.length > maxBufferedBytes) {
      _poisoned = true;
      _buffer = Uint8List(0);
      return const [];
    }
    _buffer = Uint8List.fromList([..._buffer, ...bytes]);
    final frames = <DiscordRpcFrame>[];
    var start = 0;
    while (true) {
      final available = _buffer.length - start;
      if (available < 8) break;
      final header = ByteData.sublistView(_buffer, start, start + 8);
      final opcode = DiscordRpcOpcode.fromWire(
        header.getUint32(0, Endian.little),
      );
      final length = header.getUint32(4, Endian.little);
      if (opcode == null || length > maxPayloadBytes) {
        _poisoned = true;
        _buffer = Uint8List(0);
        break;
      }
      if (available < 8 + length) break;
      final frame = _decodeBody(
        opcode,
        _buffer.sublist(start + 8, start + 8 + length),
      );
      if (frame == null) {
        _poisoned = true;
        _buffer = Uint8List(0);
        break;
      }
      frames.add(frame);
      start += 8 + length;
    }
    _buffer = start == 0 ? _buffer : _buffer.sublist(start);
    return frames;
  }

  /// Drops anything buffered, for a fresh connection sharing the decoder.
  void reset() {
    _buffer = Uint8List(0);
    _poisoned = false;
  }

  DiscordRpcFrame? _decodeBody(DiscordRpcOpcode opcode, Uint8List body) {
    if (body.isEmpty) {
      return opcode == DiscordRpcOpcode.close
          ? DiscordRpcFrame(opcode: opcode, payload: const {})
          : null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return DiscordRpcFrame(
      opcode: opcode,
      payload: decoded.cast<String, Object?>(),
    );
  }
}
