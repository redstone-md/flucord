import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flucord/src/data/discord/discord_video_rtp_sender.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// An access unit shaped the way the encoder actually emits one: a long start
/// code before the parameter sets, short ones between slices.
Uint8List _accessUnit({int sliceLength = 8}) => _bytes([
  0, 0, 0, 1, 0x67, 0x42, 0x00, // SPS
  0, 0, 0, 1, 0x68, 0xce, // PPS
  0, 0, 1, 0x65, ...List.filled(sliceLength, 0xaa), // IDR slice
]);

void main() {
  group('Annex B', () {
    test('splits on both start-code lengths', () {
      final units = DiscordH264Packetizer.splitAnnexB(_accessUnit());

      expect(units.length, 3);
      expect(units[0], [0x67, 0x42, 0x00]);
      expect(units[1], [0x68, 0xce]);
      expect(units[2].first, 0x65);
      expect(DiscordH264Packetizer.nalType(units[0]), 7);
      expect(DiscordH264Packetizer.isParameterSet(units[0]), isTrue);
      expect(DiscordH264Packetizer.isParameterSet(units[1]), isTrue);
      expect(DiscordH264Packetizer.isParameterSet(units[2]), isFalse);
    });

    test('a buffer with nothing in it yields nothing', () {
      expect(DiscordH264Packetizer.splitAnnexB(_bytes([])), isEmpty);
      expect(DiscordH264Packetizer.splitAnnexB(_bytes([1, 2, 3])), isEmpty);
      // A start code with no NAL behind it is not a unit.
      expect(DiscordH264Packetizer.splitAnnexB(_bytes([0, 0, 0, 1])), isEmpty);
      expect(
        DiscordH264Packetizer.splitAnnexB(_bytes([0, 0, 1, 0, 0, 1])),
        isEmpty,
      );
      expect(DiscordH264Packetizer.nalType(_bytes([])), 0);
    });

    test('trailing bytes after the last start code are the last unit', () {
      final units = DiscordH264Packetizer.splitAnnexB(
        _bytes([0, 0, 1, 0x41, 0x01, 0x02]),
      );

      expect(units.single, [0x41, 0x01, 0x02]);
    });
  });

  group('packetize', () {
    test('a NAL that fits is sent whole, header byte and all', () {
      final payloads = DiscordH264Packetizer.packetize(_accessUnit());

      expect(payloads.length, 3);
      expect(payloads.first.bytes.first, 0x67);
      // Only the final payload of the access unit ends the picture.
      expect(payloads.take(2).every((payload) => !payload.isLast), isTrue);
      expect(payloads.last.isLast, isTrue);
    });

    test('a NAL too large is fragmented, and reassembles to the original', () {
      final slice = _bytes([
        0x65,
        ...List.generate(300, (index) => index & 0xff),
      ]);
      final unit = _bytes([0, 0, 0, 1, ...slice]);

      final payloads = DiscordH264Packetizer.packetize(
        unit,
        maxPayloadSize: 100,
      );

      expect(payloads.length, greaterThan(1));
      // Every fragment carries the FU-A indicator with the original NAL's
      // importance bits and type 28.
      for (final payload in payloads) {
        expect(payload.bytes[0] & 0x1f, 28);
        expect(payload.bytes[0] & 0xe0, slice.first & 0xe0);
        expect(payload.bytes[1] & 0x1f, slice.first & 0x1f);
        expect(payload.bytes.length, lessThanOrEqualTo(100));
      }
      expect(payloads.first.bytes[1] & 0x80, 0x80);
      expect(payloads.first.bytes[1] & 0x40, 0);
      expect(payloads.last.bytes[1] & 0x40, 0x40);
      expect(payloads.last.bytes[1] & 0x80, 0);
      expect(payloads.last.isLast, isTrue);

      // A receiver rebuilds the NAL from the fragment header and the bodies.
      final rebuilt = <int>[
        (payloads.first.bytes[0] & 0xe0) | (payloads.first.bytes[1] & 0x1f),
        for (final payload in payloads) ...payload.bytes.skip(2),
      ];
      expect(rebuilt, slice);
    });

    test('a middle fragment is neither the start nor the end', () {
      final unit = _bytes([0, 0, 0, 1, 0x65, ...List.filled(300, 0xbb)]);

      final payloads = DiscordH264Packetizer.packetize(
        unit,
        maxPayloadSize: 60,
      );
      final middle = payloads[1];

      expect(middle.bytes[1] & 0x80, 0);
      expect(middle.bytes[1] & 0x40, 0);
    });

    test('an access unit with a fragmented NAL still marks only the end', () {
      final unit = _bytes([
        0, 0, 0, 1, 0x67, 0x42, // small parameter set
        0, 0, 0, 1, 0x65, ...List.filled(300, 0xcc), // large slice
      ]);

      final payloads = DiscordH264Packetizer.packetize(
        unit,
        maxPayloadSize: 100,
      );

      expect(payloads.where((payload) => payload.isLast).length, 1);
      expect(payloads.last.isLast, isTrue);
    });

    test('nothing to send produces no packets', () {
      expect(DiscordH264Packetizer.packetize(_bytes([])), isEmpty);
      expect(DiscordH264Packetizer.packetize(_bytes([0, 0, 0, 1])), isEmpty);
    });

    test('a payload budget with no room for a fragment header is refused', () {
      expect(
        () => DiscordH264Packetizer.packetize(_accessUnit(), maxPayloadSize: 2),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the default budget leaves room for the header and the tag', () {
      // 1200 under a 1280 MTU: 12 bytes of RTP header, the AEAD tag and the
      // extension all have to fit alongside it.
      expect(DiscordH264Packetizer.maxPayloadSize, 1200);
    });
  });

  group('rtp sender', () {
    test('numbers every packet and marks the end of each picture', () {
      final sender = DiscordVideoRtpSender(ssrc: 42);

      final packets = sender.packetsFor(
        EncodedVideoFrame(
          bytes: _accessUnit(),
          timestamp: const Duration(milliseconds: 100),
          isKeyframe: true,
        ),
      );

      expect(packets.map((packet) => packet.sequence), [0, 1, 2]);
      // One picture, one timestamp, however many packets it took.
      expect(packets.map((packet) => packet.timestamp).toSet().length, 1);
      expect(packets.last.marker, isTrue);
      expect(packets.take(2).every((packet) => !packet.marker), isTrue);
      expect(sender.sequence, 3);
      expect(sender.ssrc, 42);
    });

    test('converts the capture clock to 90kHz', () {
      expect(DiscordVideoRtpSender.timestampFor(Duration.zero), 0);
      expect(
        DiscordVideoRtpSender.timestampFor(const Duration(seconds: 1)),
        90000,
      );
      expect(
        DiscordVideoRtpSender.timestampFor(const Duration(milliseconds: 33)),
        2970,
      );
      // Past 32 bits it wraps rather than throwing, as RTP requires.
      final wrapped = DiscordVideoRtpSender.timestampFor(
        const Duration(hours: 14),
      );
      expect(wrapped, lessThanOrEqualTo(0xffffffff));
      expect(wrapped, greaterThanOrEqualTo(0));
    });

    test('the sequence wraps at sixteen bits', () {
      final sender = DiscordVideoRtpSender(ssrc: 1, initialSequence: 0xfffe);

      final packets = sender.packetsFor(
        EncodedVideoFrame(
          bytes: _accessUnit(),
          timestamp: Duration.zero,
          isKeyframe: false,
        ),
      );

      expect(packets.map((packet) => packet.sequence), [0xfffe, 0xffff, 0]);
      expect(sender.sequence, 1);
    });

    test('a frame with no NAL units advances nothing', () {
      final sender = DiscordVideoRtpSender(ssrc: 1);

      final packets = sender.packetsFor(
        EncodedVideoFrame(
          bytes: _bytes([]),
          timestamp: Duration.zero,
          isKeyframe: false,
        ),
      );

      expect(packets, isEmpty);
      // Advancing the sequence for a picture that does not exist would have a
      // receiver report the gap as loss forever.
      expect(sender.sequence, 0);
    });

    test('an initial sequence past sixteen bits is masked, not rejected', () {
      final sender = DiscordVideoRtpSender(ssrc: 1, initialSequence: 0x1_0001);

      expect(sender.sequence, 1);
    });
  });
}
