import 'dart:typed_data';

/// One RTP payload carrying part or all of an H.264 access unit.
final class H264Payload {
  const H264Payload({required this.bytes, required this.isLast});

  final Uint8List bytes;

  /// Whether this is the final payload of its access unit, which is what sets
  /// the RTP marker bit: a decoder uses it to know the picture is complete.
  final bool isLast;
}

/// Splits H.264 into RTP payloads, as RFC 6184 defines them.
///
/// The encoder hands out Annex B access units — start code, NAL, start code,
/// NAL — and RTP carries no start codes at all: each NAL is its own payload,
/// or several fragments of one when it will not fit a packet. Sending the
/// Annex B bytes straight into RTP is the mistake this exists to prevent;
/// receivers drop them silently, so nothing would ever be drawn and nothing
/// would say why.
abstract final class DiscordH264Packetizer {
  /// The largest payload that fits Discord's voice path.
  ///
  /// 1200 leaves room under a 1280-byte MTU for the RTP header, the AEAD tag
  /// and the extension the transport adds, none of which the payload knows
  /// about.
  static const maxPayloadSize = 1200;

  /// Every RTP payload for one access unit, in order.
  static List<H264Payload> packetize(
    Uint8List accessUnit, {
    int maxPayloadSize = maxPayloadSize,
  }) {
    if (maxPayloadSize <= 2) {
      throw ArgumentError.value(
        maxPayloadSize,
        'maxPayloadSize',
        'must leave room for a fragmentation header',
      );
    }
    final units = splitAnnexB(accessUnit);
    if (units.isEmpty) return const [];
    final payloads = <H264Payload>[];
    for (final unit in units) {
      payloads.addAll(_packetizeUnit(unit, maxPayloadSize));
    }
    if (payloads.isEmpty) return const [];
    // Only the very last payload of the access unit carries the marker, no
    // matter how the NALs inside it were split.
    return [
      for (var index = 0; index < payloads.length; index++)
        H264Payload(
          bytes: payloads[index].bytes,
          isLast: index == payloads.length - 1,
        ),
    ];
  }

  /// The NAL units inside an Annex B buffer, without their start codes.
  ///
  /// Both three- and four-byte start codes appear in the same stream — the
  /// encoder uses the long one before a parameter set and the short one
  /// elsewhere — so both are recognised rather than one being assumed.
  static List<Uint8List> splitAnnexB(Uint8List buffer) {
    final units = <Uint8List>[];
    var index = _nextStartCode(buffer, 0);
    if (index < 0) return const [];
    while (index < buffer.length) {
      final start = index + _startCodeLength(buffer, index);
      if (start >= buffer.length) break;
      final next = _nextStartCode(buffer, start);
      final end = next < 0 ? buffer.length : next;
      if (end > start) {
        units.add(Uint8List.sublistView(buffer, start, end));
      }
      if (next < 0) break;
      index = next;
    }
    return units;
  }

  /// The NAL type in the low five bits of a unit's first byte.
  static int nalType(Uint8List unit) => unit.isEmpty ? 0 : unit.first & 0x1f;

  /// Whether [unit] is a sequence or picture parameter set, which a decoder
  /// needs before it can make sense of anything else.
  static bool isParameterSet(Uint8List unit) {
    final type = nalType(unit);
    return type == 7 || type == 8;
  }

  static List<H264Payload> _packetizeUnit(Uint8List unit, int maxPayloadSize) {
    if (unit.isEmpty) return const [];
    if (unit.length <= maxPayloadSize) {
      // Single NAL unit mode: the payload is the NAL, header byte and all.
      return [H264Payload(bytes: unit, isLast: false)];
    }
    // FU-A: the NAL's header byte is split into an indicator that keeps its
    // importance bits and a fragment header that keeps its type, so a receiver
    // can reassemble the original byte from the pair.
    final header = unit.first;
    final indicator = (header & 0xe0) | 28;
    final type = header & 0x1f;
    final body = Uint8List.sublistView(unit, 1);
    final chunkSize = maxPayloadSize - 2;
    final payloads = <H264Payload>[];
    for (var offset = 0; offset < body.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, body.length);
      final isFirst = offset == 0;
      final isFinal = end == body.length;
      final payload = Uint8List(2 + (end - offset))
        ..[0] = indicator
        ..[1] = (isFirst ? 0x80 : 0) | (isFinal ? 0x40 : 0) | type
        ..setRange(2, 2 + (end - offset), body, offset);
      payloads.add(H264Payload(bytes: payload, isLast: false));
    }
    return payloads;
  }

  static int _nextStartCode(Uint8List buffer, int from) {
    for (var index = from; index + 2 < buffer.length; index++) {
      if (buffer[index] != 0 || buffer[index + 1] != 0) continue;
      if (buffer[index + 2] == 1) return index;
      if (index + 3 < buffer.length &&
          buffer[index + 2] == 0 &&
          buffer[index + 3] == 1) {
        return index;
      }
    }
    return -1;
  }

  static int _startCodeLength(Uint8List buffer, int index) =>
      buffer[index + 2] == 1 ? 3 : 4;
}
