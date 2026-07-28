import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_h264_depacketizer.dart';
import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// Feeds every payload of one access unit through and returns what came back.
Uint8List? _roundTrip(
  DiscordH264Depacketizer depacketizer,
  Uint8List accessUnit, {
  int maxPayloadSize = DiscordH264Packetizer.maxPayloadSize,
}) {
  Uint8List? result;
  final payloads = DiscordH264Packetizer.packetize(
    accessUnit,
    maxPayloadSize: maxPayloadSize,
  );
  for (final payload in payloads) {
    result =
        depacketizer.accept(payload.bytes, marker: payload.isLast) ?? result;
  }
  return result;
}

void main() {
  test('a round trip returns every NAL byte for byte', () {
    final accessUnit = _bytes([
      0,
      0,
      0,
      1,
      0x67,
      0x42,
      0x00,
      0,
      0,
      0,
      1,
      0x68,
      0xce,
      0,
      0,
      1,
      0x65,
      ...List.filled(40, 0xaa),
    ]);
    final depacketizer = DiscordH264Depacketizer();

    final rebuilt = _roundTrip(depacketizer, accessUnit)!;

    // Start-code lengths do not survive — RTP does not carry them — but the
    // NAL units themselves must be identical, since that is what a decoder
    // actually reads.
    expect(
      DiscordH264Packetizer.splitAnnexB(rebuilt),
      DiscordH264Packetizer.splitAnnexB(accessUnit),
    );
    expect(depacketizer.hasPendingUnit, isFalse);
  });

  test('a fragmented NAL is reassembled with its header rebuilt', () {
    final slice = _bytes([
      0x65,
      ...List.generate(500, (index) => index & 0xff),
    ]);
    final accessUnit = _bytes([0, 0, 0, 1, ...slice]);
    final depacketizer = DiscordH264Depacketizer();

    final rebuilt = _roundTrip(depacketizer, accessUnit, maxPayloadSize: 100)!;

    // The original header byte is the fragment indicator's importance bits and
    // the fragment header's type put back together.
    expect(DiscordH264Packetizer.splitAnnexB(rebuilt).single, slice);
  });

  test('a fragment whose start was lost is dropped, not half-decoded', () {
    final slice = _bytes([0x65, ...List.filled(400, 0xbb)]);
    final payloads = DiscordH264Packetizer.packetize(
      _bytes([0, 0, 0, 1, ...slice]),
      maxPayloadSize: 100,
    );
    final depacketizer = DiscordH264Depacketizer();

    // Everything but the first fragment arrives.
    Uint8List? rebuilt;
    for (final payload in payloads.skip(1)) {
      rebuilt =
          depacketizer.accept(payload.bytes, marker: payload.isLast) ?? rebuilt;
    }

    // A slice that begins in the middle is worse than no slice: the decoder
    // would try to draw it.
    expect(rebuilt, isNull);
  });

  test('a picture is only produced when the marker says so', () {
    final depacketizer = DiscordH264Depacketizer();

    expect(depacketizer.accept(_bytes([0x67, 0x42]), marker: false), isNull);
    expect(depacketizer.hasPendingUnit, isTrue);
    final rebuilt = depacketizer.accept(_bytes([0x65, 0x01]), marker: true);

    expect(DiscordH264Packetizer.splitAnnexB(rebuilt!).length, 2);
  });

  test('a STAP-A payload yields every NAL it aggregates', () {
    final depacketizer = DiscordH264Depacketizer();

    // Not something this client sends, but a sender on the other side may:
    // ignoring it would lose the parameter sets it usually carries.
    final rebuilt = depacketizer.accept(
      _bytes([
        24, // STAP-A
        0, 3, 0x67, 0x42, 0x00,
        0, 2, 0x68, 0xce,
      ]),
      marker: true,
    );

    expect(DiscordH264Packetizer.splitAnnexB(rebuilt!), [
      [0x67, 0x42, 0x00],
      [0x68, 0xce],
    ]);
  });

  test('a malformed aggregate stops rather than reading past the end', () {
    final depacketizer = DiscordH264Depacketizer();

    final rebuilt = depacketizer.accept(
      _bytes([24, 0, 9, 0x67, 0x42]),
      marker: true,
    );

    // A length that overruns the payload takes the rest of it with it.
    expect(rebuilt, isNull);
    expect(depacketizer.accept(_bytes([24, 0, 0, 0x67]), marker: true), isNull);
  });

  test('empty and truncated payloads are ignored', () {
    final depacketizer = DiscordH264Depacketizer();

    expect(depacketizer.accept(_bytes([]), marker: true), isNull);
    // A fragment payload with no body at all.
    expect(depacketizer.accept(_bytes([28, 0x85]), marker: false), isNull);
    expect(depacketizer.hasPendingUnit, isFalse);
  });

  test('parameter sets take the long start code, slices the short one', () {
    final depacketizer = DiscordH264Depacketizer();

    final rebuilt = depacketizer.accept(
      _bytes([
        24,
        0, 2, 0x67, 0x42, // SPS
        0, 2, 0x65, 0x01, // slice
      ]),
      marker: true,
    )!;

    expect(rebuilt.take(4), [0, 0, 0, 1]);
    // The slice that follows gets the three-byte code.
    expect(rebuilt.skip(6).take(3), [0, 0, 1]);
  });

  test('resetting throws away a half-assembled picture', () {
    final depacketizer = DiscordH264Depacketizer();
    final payloads = DiscordH264Packetizer.packetize(
      _bytes([0, 0, 0, 1, 0x65, ...List.filled(400, 0xcc)]),
      maxPayloadSize: 100,
    );
    depacketizer.accept(payloads.first.bytes, marker: false);
    expect(depacketizer.hasPendingUnit, isTrue);
    expect(depacketizer.pendingFragmentHeader, 0x65);

    depacketizer.reset();

    expect(depacketizer.hasPendingUnit, isFalse);
    expect(depacketizer.pendingFragmentHeader, 0);
  });

  test('a marker with nothing buffered produces nothing', () {
    final depacketizer = DiscordH264Depacketizer();

    expect(depacketizer.accept(_bytes([28, 0x05, 0x01]), marker: true), isNull);
  });
}
