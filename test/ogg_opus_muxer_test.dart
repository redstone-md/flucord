import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/ogg_opus_muxer.dart';

void main() {
  test('writes deterministic OpusHead, OpusTags, granules, and EOS pages', () {
    final encoded = OggOpusMuxer(streamSerial: 0x12345678).encode([
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList([4, 5]),
    ]);
    final pages = _parsePages(encoded);

    expect(pages, hasLength(4));
    expect(ascii.decode(pages[0].packet.sublist(0, 8)), 'OpusHead');
    expect(pages[0].headerType, 0x02);
    expect(pages[0].sequence, 0);
    expect(pages[0].serial, 0x12345678);
    final head = ByteData.sublistView(pages[0].packet);
    expect(head.getUint8(9), 2);
    expect(head.getUint16(10, Endian.little), 312);
    expect(head.getUint32(12, Endian.little), 48000);
    expect(ascii.decode(pages[1].packet.sublist(0, 8)), 'OpusTags');
    expect(pages[2].granule, 1272);
    expect(pages[3].granule, 2232);
    expect(pages[3].headerType, 0x04);
    expect(pages[3].packet, [4, 5]);
    expect(pages.every((page) => page.checksumValid), isTrue);
  });

  test('terminates a 255-byte Opus packet with a zero lacing value', () {
    final pages = _parsePages(
      OggOpusMuxer(streamSerial: 7).encode([Uint8List(255)]),
    );

    expect(pages.last.lacing, [255, 0]);
    expect(pages.last.packet, hasLength(255));
  });
}

final class _OggPage {
  const _OggPage({
    required this.headerType,
    required this.granule,
    required this.serial,
    required this.sequence,
    required this.lacing,
    required this.packet,
    required this.checksumValid,
  });

  final int headerType;
  final int granule;
  final int serial;
  final int sequence;
  final List<int> lacing;
  final Uint8List packet;
  final bool checksumValid;
}

List<_OggPage> _parsePages(Uint8List bytes) {
  final pages = <_OggPage>[];
  var offset = 0;
  while (offset < bytes.length) {
    final segmentCount = bytes[offset + 26];
    final lacing = bytes.sublist(offset + 27, offset + 27 + segmentCount);
    final bodyLength = lacing.fold<int>(0, (sum, value) => sum + value);
    final length = 27 + segmentCount + bodyLength;
    final page = Uint8List.fromList(bytes.sublist(offset, offset + length));
    final data = ByteData.sublistView(page);
    expect(ascii.decode(page.sublist(0, 4)), 'OggS');
    final storedCrc = data.getUint32(22, Endian.little);
    data.setUint32(22, 0, Endian.little);
    pages.add(
      _OggPage(
        headerType: data.getUint8(5),
        granule: data.getUint64(6, Endian.little),
        serial: data.getUint32(14, Endian.little),
        sequence: data.getUint32(18, Endian.little),
        lacing: lacing,
        packet: Uint8List.fromList(page.sublist(27 + segmentCount)),
        checksumValid: storedCrc == _oggCrc(page),
      ),
    );
    offset += length;
  }
  return pages;
}

int _oggCrc(Uint8List bytes) {
  var crc = 0;
  for (final byte in bytes) {
    final index = ((crc >> 24) & 0xff) ^ byte;
    var value = index << 24;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 0x80000000) != 0
          ? ((value << 1) ^ 0x04c11db7)
          : value << 1;
      value &= 0xffffffff;
    }
    crc = (((crc << 8) & 0xffffffff) ^ value) & 0xffffffff;
  }
  return crc;
}
