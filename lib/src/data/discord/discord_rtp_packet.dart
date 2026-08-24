import 'dart:math';
import 'dart:typed_data';

final class DiscordRtpHeader {
  DiscordRtpHeader({
    required this.sequence,
    required this.timestamp,
    required this.ssrc,
    this.payloadType = discordAudioPayloadType,
    this.marker = false,
    this.padding = false,
    List<int> csrcs = const [],
    this.extensionProfile,
    this.extensionLengthWords = 0,
  }) : csrcs = List<int>.unmodifiable(csrcs) {
    _checkUnsigned(sequence, 0xffff, 'sequence');
    _checkUnsigned(timestamp, 0xffffffff, 'timestamp');
    _checkUnsigned(ssrc, 0xffffffff, 'ssrc');
    _checkUnsigned(payloadType, 0x7f, 'payloadType');
    if (csrcs.length > 15) {
      throw RangeError.range(csrcs.length, 0, 15, 'csrcs.length');
    }
    for (final csrc in csrcs) {
      _checkUnsigned(csrc, 0xffffffff, 'csrc');
    }
    final hasExtension = extensionProfile != null;
    if (hasExtension) {
      _checkUnsigned(extensionProfile!, 0xffff, 'extensionProfile');
      _checkUnsigned(extensionLengthWords, 0xffff, 'extensionLengthWords');
    } else if (extensionLengthWords != 0) {
      throw ArgumentError.value(
        extensionLengthWords,
        'extensionLengthWords',
        'requires an extension profile',
      );
    }
  }

  /// The payload types Discord assigns the two media: Opus audio rides
  /// 0x78 and H.264 video rides 101. A picture sent on the audio one
  /// would be decoded as Opus and discarded, so the two must not meet on
  /// either connection kind: a call and a Go Live stream use the same
  /// pair.
  static const int discordAudioPayloadType = 0x78;
  static const int discordVideoPayloadType = 101;

  /// Retransmissions of video packets the far end did not get (RFC 4588),
  /// on their own SSRC one above the video's.
  static const int discordVideoRtxPayloadType = 102;
  static const int fixedLength = 12;

  final int sequence;
  final int timestamp;
  final int ssrc;
  final int payloadType;
  final bool marker;
  final bool padding;
  final List<int> csrcs;
  final int? extensionProfile;
  final int extensionLengthWords;

  bool get hasExtension => extensionProfile != null;
  int get encryptedExtensionLength => extensionLengthWords * 4;
  int get aeadAdditionalDataLength =>
      fixedLength + (csrcs.length * 4) + (hasExtension ? 4 : 0);

  Uint8List encodeAeadAdditionalData() {
    final output = Uint8List(aeadAdditionalDataLength);
    final data = ByteData.sublistView(output);
    output[0] =
        0x80 | (padding ? 0x20 : 0) | (hasExtension ? 0x10 : 0) | csrcs.length;
    output[1] = (marker ? 0x80 : 0) | payloadType;
    data.setUint16(2, sequence, Endian.big);
    data.setUint32(4, timestamp, Endian.big);
    data.setUint32(8, ssrc, Endian.big);
    var offset = fixedLength;
    for (final csrc in csrcs) {
      data.setUint32(offset, csrc, Endian.big);
      offset += 4;
    }
    if (hasExtension) {
      data.setUint16(offset, extensionProfile!, Endian.big);
      data.setUint16(offset + 2, extensionLengthWords, Endian.big);
    }
    return output;
  }

  static DiscordRtpHeader parseAeadAdditionalData(Uint8List packet) {
    if (packet.length < fixedLength) {
      throw const FormatException('RTP packet is shorter than 12 bytes');
    }
    if (packet[0] >> 6 != 2) {
      throw const FormatException('Unsupported RTP version');
    }
    final csrcCount = packet[0] & 0x0f;
    final hasExtension = packet[0] & 0x10 != 0;
    final requiredLength =
        fixedLength + (csrcCount * 4) + (hasExtension ? 4 : 0);
    if (packet.length < requiredLength) {
      throw const FormatException('Truncated RTP additional data');
    }
    final data = ByteData.sublistView(packet);
    final csrcs = <int>[];
    var offset = fixedLength;
    for (var index = 0; index < csrcCount; index++) {
      csrcs.add(data.getUint32(offset, Endian.big));
      offset += 4;
    }
    return DiscordRtpHeader(
      sequence: data.getUint16(2, Endian.big),
      timestamp: data.getUint32(4, Endian.big),
      ssrc: data.getUint32(8, Endian.big),
      payloadType: packet[1] & 0x7f,
      marker: packet[1] & 0x80 != 0,
      padding: packet[0] & 0x20 != 0,
      csrcs: List.unmodifiable(csrcs),
      extensionProfile: hasExtension
          ? data.getUint16(offset, Endian.big)
          : null,
      extensionLengthWords: hasExtension
          ? data.getUint16(offset + 2, Endian.big)
          : 0,
    );
  }
}

final class DiscordRtpFrame {
  DiscordRtpFrame({required this.header, required List<int> payload})
    : payload = List<int>.unmodifiable(payload);

  final DiscordRtpHeader header;
  final List<int> payload;

  Uint8List encodeUnencrypted() {
    final additionalData = header.encodeAeadAdditionalData();
    return Uint8List.fromList([...additionalData, ...payload]);
  }
}

final class DiscordAudioRtpPacketizer {
  DiscordAudioRtpPacketizer({
    required this.ssrc,
    required int initialSequence,
    required int initialTimestamp,
    this.samplesPerFrame = 960,
  }) : _sequence = initialSequence,
       _timestamp = initialTimestamp {
    _checkUnsigned(ssrc, 0xffffffff, 'ssrc');
    _checkUnsigned(initialSequence, 0xffff, 'initialSequence');
    _checkUnsigned(initialTimestamp, 0xffffffff, 'initialTimestamp');
    if (samplesPerFrame <= 0 || samplesPerFrame > 0xffffffff) {
      throw RangeError.range(samplesPerFrame, 1, 0xffffffff, 'samplesPerFrame');
    }
  }

  factory DiscordAudioRtpPacketizer.secure({required int ssrc}) {
    final random = Random.secure();
    return DiscordAudioRtpPacketizer(
      ssrc: ssrc,
      initialSequence: random.nextInt(0x10000),
      initialTimestamp: _randomUint32(random),
    );
  }

  final int ssrc;
  final int samplesPerFrame;
  int _sequence;
  int _timestamp;

  DiscordRtpFrame packetize(Uint8List daveFrame, {bool marker = false}) {
    final frame = DiscordRtpFrame(
      header: DiscordRtpHeader(
        sequence: _sequence,
        timestamp: _timestamp,
        ssrc: ssrc,
        marker: marker,
      ),
      payload: daveFrame,
    );
    _sequence = (_sequence + 1) & 0xffff;
    _timestamp = (_timestamp + samplesPerFrame) & 0xffffffff;
    return frame;
  }
}

void _checkUnsigned(int value, int maximum, String name) {
  if (value < 0 || value > maximum) {
    throw RangeError.range(value, 0, maximum, name);
  }
}

int _randomUint32(Random random) =>
    (random.nextInt(0x10000) << 16) | random.nextInt(0x10000);
