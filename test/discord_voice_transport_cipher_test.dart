import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_transport_cipher.dart';

void main() {
  group('DiscordVoiceTransportCipher', () {
    test('matches an independent AES-256-GCM RTP-size vector', () {
      final cipher = DiscordVoiceTransportCipher(
        mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
        secretKey: List<int>.generate(32, (index) => index),
        initialNonceCounter: 0x01020304,
      );
      addTearDown(cipher.dispose);
      final frame = DiscordRtpFrame(
        header: DiscordRtpHeader(
          sequence: 0x1234,
          timestamp: 0x10,
          ssrc: 0xdeadbeef,
        ),
        payload: [0x10, 0x20, 0x30, 0x40, 0x50],
      );

      expect(
        cipher.encryptFrame(frame),
        _hex(
          '8078123400000010deadbeef3175ed1d470a0fbf73e54d39f5b501c5422119ac0201020304',
        ),
      );
      expect(cipher.nextNonceCounter, 0x01020305);
    });

    for (final mode in DiscordVoiceTransportMode.preferred) {
      test('$mode round-trips an RTCP feedback packet', () {
      final sender = DiscordVoiceTransportCipher(
        mode: mode,
        secretKey: List<int>.generate(32, (index) => index + 3),
      );
      final receiver = DiscordVoiceTransportCipher(
        mode: mode,
        secretKey: List<int>.generate(32, (index) => index + 3),
      );
      addTearDown(sender.dispose);
      addTearDown(receiver.dispose);

      // An 8-byte RTCP header (a PLI) plus a body that gets encrypted.
      final packet = Uint8List.fromList([
        0x81, 206, 0x00, 0x03, // header
        0xde, 0xad, 0xbe, 0xef, // rest of the 8-byte header
        0xaa, 0xbb, 0xcc, 0xdd, // encrypted body
      ]);

      final recovered = receiver.decryptRtcp(sender.encryptRtcp(packet));

      // The 8 clear header bytes survive, and the body decrypts back.
      expect(recovered.sublist(0, 8), packet.sublist(0, 8));
      expect(recovered.sublist(8), [0xaa, 0xbb, 0xcc, 0xdd]);
    });

    test('$mode round-trips RTP extension payload and codec data', () {
        final sender = DiscordVoiceTransportCipher(
          mode: mode,
          secretKey: List<int>.generate(32, (index) => index + 1),
        );
        final receiver = DiscordVoiceTransportCipher(
          mode: mode,
          secretKey: List<int>.generate(32, (index) => index + 1),
        );
        addTearDown(sender.dispose);
        addTearDown(receiver.dispose);
        final frame = DiscordRtpFrame(
          header: DiscordRtpHeader(
            sequence: 7,
            timestamp: 9,
            ssrc: 11,
            csrcs: [13],
            extensionProfile: 0xbede,
            extensionLengthWords: 1,
          ),
          payload: [90, 91, 92, 93, 1, 2, 3],
        );

        final decrypted = receiver.decryptPacket(sender.encryptFrame(frame));

        expect(decrypted.header.csrcs, [13]);
        expect(decrypted.header.extensionProfile, 0xbede);
        expect(decrypted.payload, [1, 2, 3]);
      });
    }

    test('rejects modified AAD, ciphertext, tag, and nonce', () {
      final key = List<int>.filled(32, 7);
      final sender = DiscordVoiceTransportCipher(
        mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
        secretKey: key,
      );
      final receiver = DiscordVoiceTransportCipher(
        mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
        secretKey: key,
      );
      addTearDown(sender.dispose);
      addTearDown(receiver.dispose);
      final packet = sender.encryptFrame(
        DiscordRtpFrame(
          header: DiscordRtpHeader(sequence: 1, timestamp: 2, ssrc: 3),
          payload: [4, 5, 6],
        ),
      );

      for (final offset in [2, 12, packet.length - 5, packet.length - 1]) {
        final modified = Uint8List.fromList(packet)..[offset] ^= 1;
        expect(
          () => receiver.decryptPacket(modified),
          throwsA(isA<DiscordVoiceTransportAuthenticationException>()),
        );
      }
    });

    test('prevents nonce reuse after the uint32 counter is exhausted', () {
      final cipher = DiscordVoiceTransportCipher(
        mode: DiscordVoiceTransportMode.xchacha20Poly1305RtpSize,
        secretKey: List<int>.filled(32, 1),
        initialNonceCounter: 0xffffffff,
      );
      addTearDown(cipher.dispose);
      final frame = DiscordRtpFrame(
        header: DiscordRtpHeader(sequence: 1, timestamp: 2, ssrc: 3),
        payload: [4],
      );

      cipher.encryptFrame(frame);

      expect(() => cipher.encryptFrame(frame), throwsStateError);
    });

    test('validates mode, key size, packet size, and lifecycle', () {
      expect(
        () => DiscordVoiceTransportCipher(mode: 'unknown', secretKey: []),
        throwsArgumentError,
      );
      expect(
        () => DiscordVoiceTransportCipher(
          mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
          secretKey: List<int>.filled(31, 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => DiscordVoiceTransportCipher(
          mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
          secretKey: [...List<int>.filled(31, 0), 256],
        ),
        throwsArgumentError,
      );
      final cipher = DiscordVoiceTransportCipher(
        mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
        secretKey: List<int>.filled(32, 0),
      );
      expect(() => cipher.decryptPacket(Uint8List(12)), throwsFormatException);
      cipher.dispose();
      expect(() => cipher.decryptPacket(Uint8List(32)), throwsStateError);
    });
  });
}

Uint8List _hex(String value) {
  final bytes = Uint8List(value.length ~/ 2);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return bytes;
}
