import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_h264_depacketizer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// An FU-A fragment of a slice with NRI 3 and NAL type 5, so the rebuilt NAL
/// header is 0x65.
Uint8List _fragment({
  bool first = false,
  bool last = false,
  required List<int> body,
}) => _bytes([0x7c, (first ? 0x80 : 0) | (last ? 0x40 : 0) | 5, ...body]);

void main() {
  late DiscordH264Depacketizer depacketizer;

  setUp(() => depacketizer = DiscordH264Depacketizer());

  Uint8List? feed(Iterable<Uint8List> payloads) {
    for (final payload in payloads) {
      expect(depacketizer.accept(payload, marker: false), isNull);
    }
    return depacketizer.accept(_bytes([0x09, 0xf0]), marker: true);
  }

  // Every result ends with the access unit delimiter `feed` closes it with.
  const closing = [0, 0, 0, 1, 0x09, 0xf0];

  test('a whole NAL gets a four-byte start code', () {
    expect(
      feed([
        _bytes([0x41, 1, 2]),
      ]),
      [0, 0, 0, 1, 0x41, 1, 2, ...closing],
    );
  });

  test('fragments rebuild one NAL with its original header', () {
    expect(
      feed([
        _fragment(first: true, body: [1, 2]),
        _fragment(body: [3]),
        _fragment(last: true, body: [4, 5]),
      ]),
      [0, 0, 0, 1, 0x65, 1, 2, 3, 4, 5, ...closing],
    );
  });

  test('an aggregate packet gives each of its NALs a start code', () {
    expect(
      feed([
        _bytes([0x78, 0, 2, 0x67, 1, 0, 3, 0x68, 2, 3]),
      ]),
      [0, 0, 0, 1, 0x67, 1, 0, 0, 0, 1, 0x68, 2, 3, ...closing],
    );
  });

  test('a truncated aggregate keeps the NALs before the cut', () {
    expect(
      feed([
        _bytes([0x78, 0, 1, 0x67, 0, 9, 0x68]),
      ]),
      [0, 0, 0, 1, 0x67, ...closing],
    );
  });

  test('a NAL whose first fragment was lost is dropped whole', () {
    expect(
      feed([
        _bytes([0x41, 7]),
        _fragment(body: [1]),
        _fragment(last: true, body: [2]),
      ]),
      [0, 0, 0, 1, 0x41, 7, ...closing],
    );
  });

  test('a new first fragment replaces one that never finished', () {
    expect(
      feed([
        _fragment(first: true, body: [1]),
        _fragment(first: true, body: [2]),
        _fragment(last: true, body: [3]),
      ]),
      [0, 0, 0, 1, 0x65, 2, 3, ...closing],
    );
  });

  test('a picture closes without a NAL that never finished', () {
    depacketizer.accept(_bytes([0x41, 7]), marker: false);
    depacketizer.accept(_fragment(first: true, body: [1]), marker: false);

    expect(depacketizer.accept(_fragment(body: [2]), marker: true), [
      0,
      0,
      0,
      1,
      0x41,
      7,
    ]);
    expect(depacketizer.hasPendingUnit, isFalse);
  });

  test('a picture with nothing whole in it comes out as nothing', () {
    expect(depacketizer.accept(_fragment(body: [1]), marker: true), isNull);
  });

  test('payloads that are views into a larger buffer read correctly', () {
    final datagram = _bytes([0xaa, 0x41, 1, 2, 0xbb, 0x7c, 0x85, 3, 0xcc]);

    depacketizer.accept(Uint8List.sublistView(datagram, 1, 4), marker: false);
    depacketizer.accept(Uint8List.sublistView(datagram, 5, 8), marker: false);

    expect(
      depacketizer.accept(_fragment(last: true, body: [4]), marker: true),
      [0, 0, 0, 1, 0x41, 1, 2, 0, 0, 0, 1, 0x65, 3, 4],
    );
  });

  test('one picture does not leak into the next', () {
    final first = depacketizer.accept(_bytes([0x41, 1]), marker: true);
    final second = depacketizer.accept(_bytes([0x41, 2]), marker: true);

    expect(first, [0, 0, 0, 1, 0x41, 1]);
    expect(second, [0, 0, 0, 1, 0x41, 2]);
  });

  test('a reset forgets a picture still arriving', () {
    depacketizer.accept(_bytes([0x41, 1]), marker: false);
    depacketizer.accept(_fragment(first: true, body: [2]), marker: false);
    expect(depacketizer.pendingFragmentHeader, 0x65);

    depacketizer.reset();

    expect(depacketizer.hasPendingUnit, isFalse);
    expect(depacketizer.pendingFragmentHeader, 0);
    expect(depacketizer.accept(_bytes([0x41, 3]), marker: true), [
      0,
      0,
      0,
      1,
      0x41,
      3,
    ]);
  });
}
