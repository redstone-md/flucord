import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'discord_rtcp_packet.dart';
import 'discord_rtp_packet.dart';

abstract final class DiscordVoiceTransportMode {
  static const aes256GcmRtpSize = 'aead_aes256_gcm_rtpsize';
  static const xchacha20Poly1305RtpSize = 'aead_xchacha20_poly1305_rtpsize';

  static const preferred = [aes256GcmRtpSize, xchacha20Poly1305RtpSize];

  static bool isSupported(String mode) => preferred.contains(mode);
}

final class DiscordVoiceTransportAuthenticationException implements Exception {
  const DiscordVoiceTransportAuthenticationException();

  @override
  String toString() => 'Discord voice packet authentication failed';
}

final class DiscordVoiceTransportCipher {
  DiscordVoiceTransportCipher({
    required String mode,
    required List<int> secretKey,
    int initialNonceCounter = 1,
  }) : mode = mode,
       _nonceCounter = _validatedCounter(initialNonceCounter),
       _cipher = _createCipher(mode),
       _secretKey = _createSecretKey(secretKey);

  static const int authenticationTagLength = 16;
  static const int nonceSuffixLength = 4;
  static const int _maximumNonceCounter = 0xffffffff;

  final String mode;
  final _SynchronousAead _cipher;
  final SecretKeyData _secretKey;
  int _nonceCounter;
  bool _nonceExhausted = false;
  bool _disposed = false;

  int get nextNonceCounter => _nonceCounter;

  Uint8List encryptFrame(DiscordRtpFrame frame) {
    _checkActive();
    if (_nonceExhausted) {
      throw StateError('Discord voice nonce counter is exhausted');
    }

    final additionalData = frame.header.encodeAeadAdditionalData();
    final nonce = _nonceForCounter(_nonceCounter);
    final box = _cipher.encrypt(
      frame.payload,
      _secretKey,
      nonce,
      additionalData,
    );
    final packet = Uint8List(
      additionalData.length +
          box.cipherText.length +
          authenticationTagLength +
          nonceSuffixLength,
    );
    var offset = 0;
    packet.setRange(offset, offset + additionalData.length, additionalData);
    offset += additionalData.length;
    packet.setRange(offset, offset + box.cipherText.length, box.cipherText);
    offset += box.cipherText.length;
    packet.setRange(offset, offset + box.mac.bytes.length, box.mac.bytes);
    offset += box.mac.bytes.length;
    packet.setRange(offset, offset + nonceSuffixLength, nonce);

    if (_nonceCounter == _maximumNonceCounter) {
      _nonceExhausted = true;
    } else {
      _nonceCounter++;
    }
    return packet;
  }

  DiscordRtpFrame decryptPacket(Uint8List packet) {
    _checkActive();
    final header = DiscordRtpHeader.parseAeadAdditionalData(packet);
    final clearText = _open(packet, header.aeadAdditionalDataLength);
    final extensionLength = header.encryptedExtensionLength;
    if (extensionLength > clearText.length) {
      throw const FormatException('Truncated encrypted RTP extension payload');
    }
    var payload = clearText.sublist(extensionLength);
    // RFC 3550 §5.1: when the padding bit is set, the payload's last byte
    // says how many padding bytes sit behind the real payload, itself
    // included. A sender rounds some packets up, and a picture reassembled
    // with the round-up still attached is a byte count the group cipher
    // refuses, so the padding comes off where the payload is learned.
    if (header.padding && payload.isNotEmpty) {
      final count = payload.last;
      if (count > 0 && count <= payload.length) {
        payload = payload.sublist(0, payload.length - count);
      }
    }
    return DiscordRtpFrame(header: header, payload: payload);
  }

  /// Encrypts one RTCP packet the way Discord's transport does: the eight-byte
  /// header stays clear and authenticated, the rest is encrypted, and the tag
  /// and nonce trail. The receiving half of the pair is [decryptRtcp].
  ///
  /// This client only receives RTCP today, so nothing calls this in
  /// production; it is the encrypt side the decrypt side is tested against,
  /// and the one place the wire format is written down once for both.
  Uint8List encryptRtcp(Uint8List packet) {
    _checkActive();
    if (_nonceExhausted) {
      throw StateError('Discord voice nonce counter is exhausted');
    }
    if (packet.length < DiscordRtcpPacket.headerLength) {
      throw const FormatException('RTCP packet is shorter than its header');
    }
    final clear = packet.sublist(0, DiscordRtcpPacket.headerLength);
    final body = packet.sublist(DiscordRtcpPacket.headerLength);
    final nonce = _nonceForCounter(_nonceCounter);
    final box = _cipher.encrypt(body, _secretKey, nonce, clear);
    final out = Uint8List(
      clear.length +
          box.cipherText.length +
          authenticationTagLength +
          nonceSuffixLength,
    );
    var offset = 0;
    out.setRange(offset, offset += clear.length, clear);
    out.setRange(offset, offset += box.cipherText.length, box.cipherText);
    out.setRange(offset, offset += box.mac.bytes.length, box.mac.bytes);
    out.setRange(offset, offset + nonceSuffixLength, nonce);
    if (_nonceCounter == _maximumNonceCounter) {
      _nonceExhausted = true;
    } else {
      _nonceCounter++;
    }
    return out;
  }

  /// One RTCP packet in the clear: the eight-byte header it arrived with,
  /// followed by what was encrypted behind it.
  ///
  /// The same envelope as media — tag and nonce trailing — with the fixed
  /// RTCP header as the authenticated clear part where RTP has its own.
  Uint8List decryptRtcp(Uint8List packet) {
    _checkActive();
    final clearText = _open(packet, DiscordRtcpPacket.headerLength);
    return Uint8List.fromList([
      ...packet.sublist(0, DiscordRtcpPacket.headerLength),
      ...clearText,
    ]);
  }

  /// Authenticates [packet] against its first [clearLength] bytes and
  /// answers what the rest decrypted to.
  List<int> _open(Uint8List packet, int clearLength) {
    final encryptedEnd = packet.length - nonceSuffixLength;
    final tagStart = encryptedEnd - authenticationTagLength;
    if (tagStart < clearLength) {
      throw const FormatException('Truncated Discord voice AEAD packet');
    }
    final nonce = Uint8List(_cipher.nonceLength);
    nonce.setRange(
      0,
      nonceSuffixLength,
      packet,
      packet.length - nonceSuffixLength,
    );
    final box = SecretBox(
      packet.sublist(clearLength, tagStart),
      nonce: nonce,
      mac: Mac(packet.sublist(tagStart, encryptedEnd)),
    );
    return _decrypt(box, packet.sublist(0, clearLength));
  }

  List<int> _decrypt(SecretBox box, List<int> additionalData) {
    try {
      return _cipher.decrypt(box, _secretKey, additionalData);
    } on SecretBoxAuthenticationError {
      throw const DiscordVoiceTransportAuthenticationException();
    }
  }

  Uint8List _nonceForCounter(int counter) {
    final nonce = Uint8List(_cipher.nonceLength);
    ByteData.sublistView(nonce).setUint32(0, counter, Endian.big);
    return nonce;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _secretKey.destroy();
  }

  void _checkActive() {
    if (_disposed) throw StateError('Discord voice transport cipher is closed');
  }

  static _SynchronousAead _createCipher(String mode) => switch (mode) {
    DiscordVoiceTransportMode.aes256GcmRtpSize => _SynchronousAead.aes256Gcm(),
    DiscordVoiceTransportMode.xchacha20Poly1305RtpSize =>
      _SynchronousAead.xchacha20Poly1305(),
    _ => throw ArgumentError.value(mode, 'mode', 'unsupported voice mode'),
  };

  static SecretKeyData _createSecretKey(List<int> bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'secretKey.length', 'must be 32');
    }
    if (bytes.any((byte) => byte < 0 || byte > 0xff)) {
      throw ArgumentError.value(bytes, 'secretKey', 'bytes must be uint8');
    }
    return SecretKeyData(
      Uint8List.fromList(bytes),
      overwriteWhenDestroyed: true,
      debugLabel: 'Discord voice transport key',
    );
  }

  static int _validatedCounter(int value) {
    if (value < 0 || value > _maximumNonceCounter) {
      throw RangeError.range(
        value,
        0,
        _maximumNonceCounter,
        'initialNonceCounter',
      );
    }
    return value;
  }
}

typedef _EncryptAead =
    SecretBox Function(
      List<int> clearText,
      SecretKeyData secretKey,
      List<int> nonce,
      List<int> additionalData,
    );
typedef _DecryptAead =
    List<int> Function(
      SecretBox box,
      SecretKeyData secretKey,
      List<int> additionalData,
    );

final class _SynchronousAead {
  const _SynchronousAead({
    required this.nonceLength,
    required this.encrypt,
    required this.decrypt,
  });

  factory _SynchronousAead.aes256Gcm() {
    final cipher = AesGcm.with256bits().toSync();
    return _SynchronousAead(
      nonceLength: cipher.nonceLength,
      encrypt: (clearText, key, nonce, aad) => cipher.encryptSync(
        clearText,
        secretKeyData: key,
        nonce: nonce,
        aad: aad,
      ),
      decrypt: (box, key, aad) =>
          cipher.decryptSync(box, secretKeyData: key, aad: aad),
    );
  }

  factory _SynchronousAead.xchacha20Poly1305() {
    final cipher = Xchacha20.poly1305Aead().toSync();
    return _SynchronousAead(
      nonceLength: cipher.nonceLength,
      encrypt: (clearText, key, nonce, aad) =>
          cipher.encryptSync(clearText, secretKey: key, nonce: nonce, aad: aad),
      decrypt: (box, key, aad) =>
          cipher.decryptSync(box, secretKey: key, aad: aad),
    );
  }

  final int nonceLength;
  final _EncryptAead encrypt;
  final _DecryptAead decrypt;
}
