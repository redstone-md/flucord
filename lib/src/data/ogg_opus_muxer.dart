import 'dart:convert';
import 'dart:typed_data';

final class OggOpusMuxer {
  OggOpusMuxer({int? streamSerial})
    : _streamSerial =
          streamSerial ??
          (DateTime.now().microsecondsSinceEpoch & _unsigned32Mask);

  static const int _unsigned32Mask = 0xffffffff;
  static const int _preSkip = 312;
  static const int _sampleRate = 48000;
  static const int _samplesPerPacket = 960;

  final int _streamSerial;

  Uint8List encode(List<Uint8List> packets) {
    if (packets.isEmpty) {
      throw ArgumentError('At least one Opus packet is required');
    }
    final output = BytesBuilder(copy: false);
    var sequence = 0;
    output.add(
      _page(
        packet: _opusHead(),
        granulePosition: 0,
        sequence: sequence++,
        headerType: 0x02,
      ),
    );
    output.add(
      _page(
        packet: _opusTags(),
        granulePosition: 0,
        sequence: sequence++,
        headerType: 0,
      ),
    );
    for (var index = 0; index < packets.length; index++) {
      final isLast = index == packets.length - 1;
      output.add(
        _page(
          packet: packets[index],
          granulePosition: _preSkip + (index + 1) * _samplesPerPacket,
          sequence: sequence++,
          headerType: isLast ? 0x04 : 0,
        ),
      );
    }
    return output.takeBytes();
  }

  Uint8List _opusHead() {
    final bytes = Uint8List(19);
    bytes.setRange(0, 8, ascii.encode('OpusHead'));
    final data = ByteData.sublistView(bytes);
    data.setUint8(8, 1);
    data.setUint8(9, 2);
    data.setUint16(10, _preSkip, Endian.little);
    data.setUint32(12, _sampleRate, Endian.little);
    data.setInt16(16, 0, Endian.little);
    data.setUint8(18, 0);
    return bytes;
  }

  Uint8List _opusTags() {
    final vendor = utf8.encode('Flucord');
    final bytes = Uint8List(8 + 4 + vendor.length + 4);
    bytes.setRange(0, 8, ascii.encode('OpusTags'));
    final data = ByteData.sublistView(bytes);
    data.setUint32(8, vendor.length, Endian.little);
    bytes.setRange(12, 12 + vendor.length, vendor);
    data.setUint32(12 + vendor.length, 0, Endian.little);
    return bytes;
  }

  Uint8List _page({
    required Uint8List packet,
    required int granulePosition,
    required int sequence,
    required int headerType,
  }) {
    final lacing = <int>[];
    var remaining = packet.length;
    while (remaining >= 255) {
      lacing.add(255);
      remaining -= 255;
    }
    lacing.add(remaining);
    if (lacing.length > 255) throw StateError('Opus packet exceeds Ogg page');

    final bytes = Uint8List(27 + lacing.length + packet.length);
    bytes.setRange(0, 4, ascii.encode('OggS'));
    final data = ByteData.sublistView(bytes);
    data.setUint8(4, 0);
    data.setUint8(5, headerType);
    data.setUint64(6, granulePosition, Endian.little);
    data.setUint32(14, _streamSerial & _unsigned32Mask, Endian.little);
    data.setUint32(18, sequence, Endian.little);
    data.setUint32(22, 0, Endian.little);
    data.setUint8(26, lacing.length);
    bytes.setRange(27, 27 + lacing.length, lacing);
    bytes.setRange(27 + lacing.length, bytes.length, packet);
    data.setUint32(22, _crc(bytes), Endian.little);
    return bytes;
  }

  static int _crc(Uint8List bytes) {
    var crc = 0;
    for (final byte in bytes) {
      final index = ((crc >> 24) & 0xff) ^ byte;
      crc =
          (((crc << 8) & _unsigned32Mask) ^ _crcTable[index]) & _unsigned32Mask;
    }
    return crc;
  }

  static final List<int> _crcTable = List.generate(256, (index) {
    var value = index << 24;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 0x80000000) != 0
          ? ((value << 1) ^ 0x04c11db7)
          : value << 1;
      value &= _unsigned32Mask;
    }
    return value;
  }, growable: false);
}
