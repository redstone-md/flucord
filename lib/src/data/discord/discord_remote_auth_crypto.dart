import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final class DiscordRemoteAuthCrypto {
  DiscordRemoteAuthCrypto._(this._privateKey, this.encodedPublicKey);

  final RSAPrivateKey _privateKey;
  final String encodedPublicKey;

  static Future<DiscordRemoteAuthCrypto> generate() async {
    final parts = await Isolate.run(_generateKeyParts);
    return DiscordRemoteAuthCrypto._(
      RSAPrivateKey(
        BigInt.parse(parts[0]),
        BigInt.parse(parts[1]),
        BigInt.parse(parts[2]),
        BigInt.parse(parts[3]),
      ),
      parts[4],
    );
  }

  Uint8List decrypt(String encodedCiphertext) {
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(_privateKey));
    return cipher.process(_decodeBase64(encodedCiphertext));
  }

  String nonceProof(String encodedNonce) {
    final digest = SHA256Digest().process(decrypt(encodedNonce));
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  String decryptText(String encodedCiphertext) =>
      utf8.decode(decrypt(encodedCiphertext));

  static List<String> _generateKeyParts() {
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(_secureBytes(32))));
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    final publicKey = pair.publicKey;
    final privateKey = pair.privateKey;
    return [
      privateKey.modulus!.toString(),
      privateKey.privateExponent!.toString(),
      privateKey.p!.toString(),
      privateKey.q!.toString(),
      base64Encode(_subjectPublicKeyInfo(publicKey)),
    ];
  }

  static List<int> _secureBytes(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(256));
  }

  static Uint8List _subjectPublicKeyInfo(RSAPublicKey key) {
    final rsaKey = _sequence([_integer(key.modulus!), _integer(key.exponent!)]);
    final algorithm = _sequence([
      Uint8List.fromList([
        0x06,
        0x09,
        0x2a,
        0x86,
        0x48,
        0x86,
        0xf7,
        0x0d,
        0x01,
        0x01,
        0x01,
      ]),
      Uint8List.fromList([0x05, 0x00]),
    ]);
    return _sequence([
      algorithm,
      _tagged(0x03, Uint8List.fromList([0, ...rsaKey])),
    ]);
  }

  static Uint8List _integer(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    var bytes = Uint8List.fromList([
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ]);
    if (bytes.first >= 0x80) bytes = Uint8List.fromList([0, ...bytes]);
    return _tagged(0x02, bytes);
  }

  static Uint8List _sequence(List<Uint8List> values) => _tagged(
    0x30,
    Uint8List.fromList(values.expand((value) => value).toList()),
  );

  static Uint8List _tagged(int tag, Uint8List value) =>
      Uint8List.fromList([tag, ..._length(value.length), ...value]);

  static List<int> _length(int length) {
    if (length < 0x80) return [length];
    final bytes = <int>[];
    for (var remaining = length; remaining > 0; remaining >>= 8) {
      bytes.insert(0, remaining & 0xff);
    }
    return [0x80 | bytes.length, ...bytes];
  }

  static Uint8List _decodeBase64(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padding = '=' * ((4 - normalized.length % 4) % 4);
    return base64Decode('$normalized$padding');
  }

  @override
  String toString() => 'DiscordRemoteAuthCrypto(<private key redacted>)';
}
