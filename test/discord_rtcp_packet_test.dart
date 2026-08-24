import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtcp_packet.dart';
import 'package:flutter_test/flutter_test.dart';

/// An RTCP packet header: two version bits, the report count, the type, and a
/// length in 32-bit words minus one.
Uint8List _packet(int count, int type, List<int> body) {
  // The length field is the whole packet in 32-bit words minus one; with a
  // one-word header that is exactly the body's word count.
  final bodyWords = body.length ~/ 4;
  return Uint8List.fromList([
    0x80 | count,
    type,
    0,
    bodyWords,
    ...body,
  ]);
}

List<int> _u32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

void main() {
  test('a picture-loss indication asks for a keyframe', () {
    final reports = DiscordRtcpPacket.parse(
      _packet(1, DiscordRtcpPacket.payloadFeedback, [
        ..._u32(0x1111), // sender
        ..._u32(0x2222), // media source
      ]),
    );

    expect(reports, hasLength(1));
    expect(reports.single, isA<DiscordRtcpPictureLoss>());
    expect((reports.single as DiscordRtcpPictureLoss).mediaSsrc, 0x2222);
  });

  test('a NACK names the packet and the fifteen after it by bitmask', () {
    final reports = DiscordRtcpPacket.parse(
      _packet(1, DiscordRtcpPacket.transportFeedback, [
        ..._u32(0x1111), // sender
        ..._u32(0x2222), // media source
        // packet id 100, bitmask with bit 0 and bit 2 set -> 100, 101, 103.
        0x00, 0x64, 0x00, 0x05,
      ]),
    );

    expect(reports, hasLength(1));
    final nack = reports.single as DiscordRtcpNack;
    expect(nack.mediaSsrc, 0x2222);
    expect(nack.sequences, [100, 101, 103]);
  });

  test('a receiver report carries the loss fraction and cumulative count', () {
    final reports = DiscordRtcpPacket.parse(
      _packet(1, DiscordRtcpPacket.receiverReport, [
        ..._u32(0x1111), // reporter
        ..._u32(0x2222), // the ssrc this block is about
        // fraction 128/256, cumulative 10.
        0x80, 0x00, 0x00, 0x0a,
        ..._u32(0), // extended highest sequence
        ..._u32(0x1234), // jitter
        ..._u32(0), // last SR
        ..._u32(0), // delay since last SR
      ]),
    );

    expect(reports, hasLength(1));
    final report = reports.single as DiscordRtcpReceiverReport;
    expect(report.ssrc, 0x2222);
    expect(report.lossRatio, closeTo(0.5, 0.001));
    expect(report.cumulativeLost, 10);
    expect(report.jitter, 0x1234);
  });

  test('a negative cumulative loss is read as signed', () {
    final reports = DiscordRtcpPacket.parse(
      _packet(1, DiscordRtcpPacket.receiverReport, [
        ..._u32(0x1111),
        ..._u32(0x2222),
        0x00, 0xff, 0xff, 0xfe, // fraction 0, cumulative -2
        ..._u32(0),
        ..._u32(0),
        ..._u32(0),
        ..._u32(0),
      ]),
    );

    expect((reports.single as DiscordRtcpReceiverReport).cumulativeLost, -2);
  });

  test('several reports in one compound packet are all read', () {
    final pli = _packet(1, DiscordRtcpPacket.payloadFeedback, [
      ..._u32(0x1111),
      ..._u32(0x2222),
    ]);
    final nack = _packet(1, DiscordRtcpPacket.transportFeedback, [
      ..._u32(0x1111),
      ..._u32(0x2222),
      0x00, 0x0a, 0x00, 0x00, // just packet 10
    ]);

    final reports =
        DiscordRtcpPacket.parse(Uint8List.fromList([...pli, ...nack]));

    expect(reports, hasLength(2));
    expect(reports[0], isA<DiscordRtcpPictureLoss>());
    expect((reports[1] as DiscordRtcpNack).sequences, [10]);
  });

  test('a truncated packet ends the read rather than throwing', () {
    // A length that claims more than the bytes present.
    final report = Uint8List.fromList([
      0x81,
      DiscordRtcpPacket.receiverReport,
      0,
      10, // claims 44 bytes, only 8 present
      ..._u32(0x1111),
    ]);

    expect(DiscordRtcpPacket.parse(report), isEmpty);
  });

  test('isRtcp accepts the feedback types and rejects RTP', () {
    expect(
      DiscordRtcpPacket.isRtcp(Uint8List.fromList([0x80, 206, 0, 0, 0, 0, 0, 0])),
      isTrue,
    );
    // Payload type 101 is video RTP, not RTCP.
    expect(
      DiscordRtcpPacket.isRtcp(Uint8List.fromList([0x80, 101, 0, 0, 0, 0, 0, 0])),
      isFalse,
    );
  });
}
