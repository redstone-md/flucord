import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';

void main() {
  test('encodes Discord audio RTP fields and advances Opus time', () {
    final packetizer = DiscordAudioRtpPacketizer(
      ssrc: 0xdeadbeef,
      initialSequence: 0x1234,
      initialTimestamp: 0x10,
    );

    final first = packetizer.packetize(Uint8List.fromList([1, 2, 3]));
    final second = packetizer.packetize(Uint8List.fromList([4]));

    expect(first.encodeUnencrypted(), [
      0x80,
      0x78,
      0x12,
      0x34,
      0,
      0,
      0,
      0x10,
      0xde,
      0xad,
      0xbe,
      0xef,
      1,
      2,
      3,
    ]);
    expect(second.header.sequence, 0x1235);
    expect(second.header.timestamp, 0x10 + 960);
  });

  test('wraps RTP sequence and timestamp counters', () {
    final packetizer = DiscordAudioRtpPacketizer(
      ssrc: 1,
      initialSequence: 0xffff,
      initialTimestamp: 0xfffffff0,
      samplesPerFrame: 32,
    );

    packetizer.packetize(Uint8List(0));
    final wrapped = packetizer.packetize(Uint8List(0));

    expect(wrapped.header.sequence, 0);
    expect(wrapped.header.timestamp, 0x10);
  });

  test('parses RTP-size AAD with CSRC and extension preamble', () {
    final packet = Uint8List.fromList([
      0x91,
      0xf8,
      0,
      7,
      0,
      0,
      0,
      9,
      0,
      0,
      0,
      11,
      0,
      0,
      0,
      13,
      0xbe,
      0xde,
      0,
      2,
      99,
      98,
    ]);

    final header = DiscordRtpHeader.parseAeadAdditionalData(packet);

    expect(header.marker, isTrue);
    expect(header.payloadType, 0x78);
    expect(header.csrcs, [13]);
    expect(header.extensionProfile, 0xbede);
    expect(header.encryptedExtensionLength, 8);
    expect(header.aeadAdditionalDataLength, 20);
    expect(header.encodeAeadAdditionalData(), packet.sublist(0, 20));
  });

  test('rejects invalid or truncated RTP headers', () {
    expect(
      () => DiscordRtpHeader.parseAeadAdditionalData(Uint8List(11)),
      throwsFormatException,
    );
    final wrongVersion = Uint8List(12)..[0] = 0x40;
    expect(
      () => DiscordRtpHeader.parseAeadAdditionalData(wrongVersion),
      throwsFormatException,
    );
    final truncatedCsrc = Uint8List(12)..[0] = 0x81;
    expect(
      () => DiscordRtpHeader.parseAeadAdditionalData(truncatedCsrc),
      throwsFormatException,
    );
  });
}
