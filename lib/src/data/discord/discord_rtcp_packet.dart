import 'dart:typed_data';

/// What the far end said about this client's pictures, one report at a time.
sealed class DiscordRtcpReport {
  const DiscordRtcpReport();
}

/// One report block of a receiver or sender report (RFC 3550 §6.4).
final class DiscordRtcpReceiverReport extends DiscordRtcpReport {
  const DiscordRtcpReceiverReport({
    required this.ssrc,
    required this.fractionLost,
    required this.cumulativeLost,
    required this.jitter,
  });

  /// Whose packets the block is about.
  final int ssrc;

  /// Packets lost since the last report, in 1/256ths.
  final int fractionLost;

  /// Packets lost since the beginning, which the sender can go negative on
  /// when duplicates arrive.
  final int cumulativeLost;

  /// Interarrival jitter, in RTP timestamp units.
  final int jitter;

  double get lossRatio => fractionLost / 256;
}

/// The packets a receiver did not get (RFC 4585 §6.2.1).
final class DiscordRtcpNack extends DiscordRtcpReport {
  const DiscordRtcpNack({required this.mediaSsrc, required this.sequences});

  final int mediaSsrc;
  final List<int> sequences;
}

/// A picture-loss indication (RFC 4585 §6.3.1): a receiver cannot decode
/// what is arriving and needs a keyframe.
final class DiscordRtcpPictureLoss extends DiscordRtcpReport {
  const DiscordRtcpPictureLoss({required this.mediaSsrc});

  final int mediaSsrc;
}

/// Reads the RTCP feedback the media server relays for the pictures this
/// client sends.
///
/// Only the reports a sender acts on are read; everything else in a compound
/// packet is stepped over by its length. A truncated packet ends the read
/// rather than throwing: feedback is advisory, and the next one is a second
/// away.
abstract final class DiscordRtcpPacket {
  static const senderReport = 200;
  static const receiverReport = 201;
  static const transportFeedback = 205;
  static const payloadFeedback = 206;

  /// The eight bytes every RTCP packet starts with, sent in the clear.
  static const headerLength = 8;

  /// Whether [packet] is typed as RTCP rather than RTP: the payload types
  /// 192-223 are ones RTP never uses.
  static bool isRtcp(Uint8List packet) =>
      packet.length >= headerLength && packet[1] >= 192 && packet[1] <= 223;

  /// Every report this client acts on in one compound packet.
  static List<DiscordRtcpReport> parse(Uint8List compound) {
    final reports = <DiscordRtcpReport>[];
    final data = ByteData.sublistView(compound);
    var offset = 0;
    while (offset + headerLength <= compound.length) {
      final first = compound[offset];
      if (first >> 6 != 2) break;
      final count = first & 0x1f;
      final type = compound[offset + 1];
      final length = (data.getUint16(offset + 2, Endian.big) + 1) * 4;
      final end = offset + length;
      if (end > compound.length) break;
      switch (type) {
        case senderReport:
          // Twenty bytes of sender information before the report blocks.
          _readReportBlocks(data, offset + 28, end, count, reports);
        case receiverReport:
          _readReportBlocks(data, offset + 8, end, count, reports);
        case transportFeedback when count == 1:
          reports.add(_readNack(data, offset + 8, end));
        case payloadFeedback when count == 1:
          if (offset + 12 <= end) {
            reports.add(
              DiscordRtcpPictureLoss(
                mediaSsrc: data.getUint32(offset + 8, Endian.big),
              ),
            );
          }
      }
      offset = end;
    }
    return reports;
  }

  /// Writes a transport-feedback generic NACK (RFC 4585 §6.2.1): the
  /// sequence numbers this receiver is still owed, packed as packet ids with
  /// a bitmask of the fifteen behind each.
  static Uint8List nack({
    required int senderSsrc,
    required int mediaSsrc,
    required List<int> sequences,
  }) {
    final entries = <int, int>{};
    for (final sequence in sequences) {
      var placed = false;
      for (final id in entries.keys.toList()) {
        final bit = (sequence - id - 1) & 0xffff;
        if (bit < 16 && entries[id]! & (1 << bit) == 0) {
          entries[id] = entries[id]! | (1 << bit);
          placed = true;
          break;
        }
      }
      if (!placed) entries[sequence] = 0;
    }
    final packet = Uint8List(12 + 4 * entries.length);
    final data = ByteData.sublistView(packet);
    packet[0] = 0x81; // version 2, FMT 1: generic NACK
    packet[1] = transportFeedback;
    data.setUint16(2, (packet.length ~/ 4) - 1, Endian.big);
    data.setUint32(4, senderSsrc, Endian.big);
    data.setUint32(8, mediaSsrc, Endian.big);
    var offset = 12;
    for (final id in entries.keys) {
      data.setUint16(offset, id, Endian.big);
      data.setUint16(offset + 2, entries[id]!, Endian.big);
      offset += 4;
    }
    return packet;
  }

  /// Writes a picture-loss indication (RFC 4585 §6.3.1): a request that the
  /// sender send a keyframe, because the references this receiver holds are
  /// broken.
  static Uint8List pictureLoss({
    required int senderSsrc,
    required int mediaSsrc,
  }) {
    final packet = Uint8List(12);
    final data = ByteData.sublistView(packet);
    packet[0] = 0x81; // version 2, FMT 1: PLI
    packet[1] = payloadFeedback;
    data.setUint16(2, 2, Endian.big);
    data.setUint32(4, senderSsrc, Endian.big);
    data.setUint32(8, mediaSsrc, Endian.big);
    return packet;
  }

  /// Writes a Full Intra Request (RFC 5104 §4.3.1): the same ask as PLI in
  /// the other payload-specific feedback format. Sent alongside PLI because
  /// implementations answer one or the other, and a stream that keeps
  /// smearing cannot afford to find out which only by waiting.
  static Uint8List fullIntraRequest({
    required int senderSsrc,
    required int mediaSsrc,
    required int commandSequence,
  }) {
    final packet = Uint8List(20);
    final data = ByteData.sublistView(packet);
    packet[0] = 0x84; // version 2, FMT 4: FIR
    packet[1] = payloadFeedback;
    data.setUint16(2, 4, Endian.big);
    data.setUint32(4, senderSsrc, Endian.big);
    data.setUint32(8, mediaSsrc, Endian.big);
    // FCI: the media source asked for, then its command sequence number.
    data.setUint32(12, mediaSsrc, Endian.big);
    data.setUint32(16, commandSequence & 0xff, Endian.big);
    return packet;
  }

  static void _readReportBlocks(
    ByteData data,
    int offset,
    int end,
    int count,
    List<DiscordRtcpReport> reports,
  ) {
    for (var index = 0; index < count && offset + 24 <= end; index++) {
      final lostField = data.getUint32(offset + 4, Endian.big);
      // A signed 24-bit count behind the 8-bit fraction.
      var cumulativeLost = lostField & 0xffffff;
      if (cumulativeLost & 0x800000 != 0) cumulativeLost -= 0x1000000;
      reports.add(
        DiscordRtcpReceiverReport(
          ssrc: data.getUint32(offset, Endian.big),
          fractionLost: lostField >> 24,
          cumulativeLost: cumulativeLost,
          jitter: data.getUint32(offset + 12, Endian.big),
        ),
      );
      offset += 24;
    }
  }

  /// A NACK names a packet and a bitmask of the fifteen after it, and
  /// repeats the pair for as long as the packet lasts.
  static DiscordRtcpNack _readNack(ByteData data, int offset, int end) {
    final mediaSsrc = offset + 4 <= end ? data.getUint32(offset, Endian.big) : 0;
    final sequences = <int>[];
    for (var at = offset + 4; at + 4 <= end; at += 4) {
      final packetId = data.getUint16(at, Endian.big);
      final bitmask = data.getUint16(at + 2, Endian.big);
      sequences.add(packetId);
      for (var bit = 0; bit < 16; bit++) {
        if (bitmask & (1 << bit) != 0) {
          sequences.add((packetId + bit + 1) & 0xffff);
        }
      }
    }
    return DiscordRtcpNack(mediaSsrc: mediaSsrc, sequences: sequences);
  }
}
