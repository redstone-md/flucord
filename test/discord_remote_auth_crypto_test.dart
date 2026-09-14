import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_remote_auth_crypto.dart';
import 'package:pointycastle/export.dart';

void main() {
  test('exports SPKI and decrypts Discord OAEP SHA-256 payloads', () async {
    final crypto = await DiscordRemoteAuthCrypto.generate();
    final publicKey = _readPublicKey(base64Decode(crypto.encodedPublicKey));
    final encryptor = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    final plaintext = Uint8List.fromList(utf8.encode('remote-auth-payload'));
    final encrypted = encryptor.process(plaintext);
    final encoded = base64Encode(encrypted);

    expect(crypto.decryptText(encoded), 'remote-auth-payload');
    expect(
      crypto.nonceProof(encoded),
      base64UrlEncode(SHA256Digest().process(plaintext)).replaceAll('=', ''),
    );
    expect(crypto.toString(), isNot(contains(crypto.encodedPublicKey)));
  });
}

RSAPublicKey _readPublicKey(Uint8List bytes) {
  final outer = _DerReader(bytes).element(0x30);
  outer.element(0x30);
  final bitString = outer.element(0x03);
  expect(bitString.readByte(), 0);
  final key = bitString.element(0x30);
  final modulus = key.integer();
  final exponent = key.integer();
  return RSAPublicKey(modulus, exponent);
}

final class _DerReader {
  _DerReader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  int readByte() => bytes[offset++];

  _DerReader element(int expectedTag) {
    expect(readByte(), expectedTag);
    final length = _readLength();
    final value = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return _DerReader(value);
  }

  BigInt integer() {
    final value = element(0x02).bytes;
    return BigInt.parse(
      value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
  }

  int _readLength() {
    final first = readByte();
    if (first < 0x80) return first;
    var result = 0;
    for (var index = 0; index < (first & 0x7f); index++) {
      result = (result << 8) | readByte();
    }
    return result;
  }
}
