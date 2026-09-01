import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flucord/src/data/discord/discord_video_picture_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// Stands in for the group cipher, and refuses anything but a whole picture.
///
/// Real group encryption authenticates the picture the sender encrypted, so a
/// fragment of one does not decrypt. That is the whole reason a receiver has
/// to reassemble before it decrypts, and a fake that accepted any bytes at all
/// would happily pass against an order that is wrong.
final class _FakeGroupCipher {
  final List<int> seen = [];

  /// What a sender puts on the wire: the picture, sealed.
  Uint8List seal(Uint8List unit) => _bytes([...unit, ..._tag]);

  Uint8List open(Uint8List sealed) {
    seen.add(sealed.length);
    if (!_endsWith(sealed, _tag)) {
      throw StateError('not a whole picture: ${sealed.length} bytes');
    }
    return Uint8List.sublistView(sealed, 0, sealed.length - _tag.length);
  }

  /// In the place of an authentication tag, and never a start code, so the
  /// Annex B structure a packetiser reads survives being sealed.
  static const _tag = [0xde, 0xad, 0xbe, 0xef];
}

bool _endsWith(Uint8List bytes, List<int> tail) {
  final offset = bytes.length - tail.length;
  if (offset < 0) return false;
  for (var index = 0; index < tail.length; index++) {
    if (bytes[offset + index] != tail[index]) return false;
  }
  return true;
}

/// A parameter set and a slice, long enough to span several packets.
Uint8List _accessUnit({required int sliceLength}) => _bytes([
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
  ...List.filled(sliceLength, 0xaa),
]);

/// Feeds every payload of one access unit through, and returns the last thing
/// that came out.
DiscordPicture? _feed(
  DiscordVideoPictureReceiver receiver,
  Uint8List unit, {
  int maxPayloadSize = DiscordH264Packetizer.maxPayloadSize,
  int rtpTimestamp = 0,
}) {
  DiscordPicture? result;
  for (final payload in DiscordH264Packetizer.packetize(
    unit,
    maxPayloadSize: maxPayloadSize,
  )) {
    result =
        receiver.accept(
          payload.bytes,
          marker: payload.isLast,
          rtpTimestamp: rtpTimestamp,
        ) ??
        result;
  }
  return result;
}

/// A picture that references an earlier one: no IDR slice inside.
Uint8List _nonIdrAccessUnit({required int sliceLength}) => _bytes([
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
  0,
  1,
  0x41,
  ...List.filled(sliceLength, 0xaa),
]);

void main() {
  test('a picture spanning several packets is decrypted once, as a whole', () {
    final cipher = _FakeGroupCipher();
    final unit = _accessUnit(sliceLength: 500);
    final sealed = cipher.seal(unit);
    final payloads = DiscordH264Packetizer.packetize(
      sealed,
      maxPayloadSize: 100,
    );
    // The case under test: one picture, many packets.
    expect(payloads.length, greaterThan(1));
    final receiver = DiscordVideoPictureReceiver(decryptor: cipher.open);

    for (final payload in payloads.take(payloads.length - 1)) {
      expect(receiver.accept(payload.bytes, marker: payload.isLast), isNull);
    }
    final result = receiver.accept(
      payloads.last.bytes,
      marker: payloads.last.isLast,
    )!;
    expect(result.rtpTimestamp, isZero);

    // Once, and on the reassembled picture rather than on a packet.
    expect(cipher.seen, [sealed.length]);
    expect(
      DiscordH264Packetizer.splitAnnexB(result.bytes),
      DiscordH264Packetizer.splitAnnexB(unit),
    );
  });

  test('a picture that fits one packet is decrypted once too', () {
    final cipher = _FakeGroupCipher();
    final unit = _accessUnit(sliceLength: 40);
    final receiver = DiscordVideoPictureReceiver(decryptor: cipher.open);

    final result = _feed(receiver, cipher.seal(unit));

    expect(cipher.seen, hasLength(1));
    expect(
      DiscordH264Packetizer.splitAnnexB(result!.bytes),
      DiscordH264Packetizer.splitAnnexB(unit),
    );
  });

  test('a room with no group hands the reassembled picture on untouched', () {
    final unit = _accessUnit(sliceLength: 40);
    final receiver = DiscordVideoPictureReceiver();

    final result = _feed(receiver, unit);

    // No decryptor is not the same as a decryptor that does nothing: the
    // payloads were never sealed, and come back as the encoder made them.
    expect(
      DiscordH264Packetizer.splitAnnexB(result!.bytes),
      DiscordH264Packetizer.splitAnnexB(unit),
    );
  });

  test('a picture that will not decrypt is dropped, and does not jam the next',
      () {
        final cipher = _FakeGroupCipher();
        final receiver = DiscordVideoPictureReceiver(decryptor: cipher.open);
        final unit = _accessUnit(sliceLength: 40);

        // A picture from before this client had a key for it.
        expect(_feed(receiver, unit), isNull);

        final next = _feed(receiver, cipher.seal(unit));

        expect(
          DiscordH264Packetizer.splitAnnexB(next!.bytes),
          DiscordH264Packetizer.splitAnnexB(unit),
        );
      });

  test('a lost picture keeps the keyframe ask going until an IDR arrives', () {
    var clock = DateTime(2026, 1, 1);
    var asks = 0;
    final cipher = _FakeGroupCipher();
    final receiver = DiscordVideoPictureReceiver(
      decryptor: cipher.open,
      onPictureLoss: () => asks++,
      now: () => clock,
    );
    final pFrame = _nonIdrAccessUnit(sliceLength: 40);
    final idrFrame = _accessUnit(sliceLength: 40);

    // The lost picture: it fails to open, and that alone breaks the chain.
    expect(_feed(receiver, pFrame), isNull);
    expect(asks, 1);

    // Later pictures open fine and still draw garbage: the ask must go on.
    clock = clock.add(const Duration(seconds: 2));
    _feed(receiver, cipher.seal(pFrame));
    expect(asks, 2);

    // A real keyframe proves the references are whole; the asking stops.
    clock = clock.add(const Duration(seconds: 2));
    _feed(receiver, cipher.seal(idrFrame));
    expect(asks, 2);
    clock = clock.add(const Duration(seconds: 2));
    _feed(receiver, cipher.seal(pFrame));
    expect(asks, 2);
  });
}
