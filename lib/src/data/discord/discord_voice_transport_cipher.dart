import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

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
    final additionalDataLength = header.aeadAdditionalDataLength;
    final encryptedEnd = packet.length - nonceSuffixLength;
    final tagStart = encryptedEnd - authenticationTagLength;
    if (tagStart < additionalDataLength) {
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
      packet.sublist(additionalDataLength, tagStart),
      nonce: nonce,
      mac: Mac(packet.sublist(tagStart, encryptedEnd)),
    );
    final clearText = _decrypt(box, packet.sublist(0, additionalDataLength));
    final extensionLength = header.encryptedExtensionLength;
    if (extensionLength > clearText.length) {
      throw const FormatException('Truncated encrypted RTP extension payload');
    }
    return DiscordRtpFrame(
      header: header,
      payload: clearText.sublist(extensionLength),
    );
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
