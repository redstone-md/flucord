import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/dave/native_dave_service.dart';
import 'package:flucord/src/domain/voice_dave.dart';

void main() {
  test('loads official libdave and owns an MLS session', () {
    final service = NativeDaveService.open(
      libraryPath: 'windows/third_party/libdave/libdave.dll',
    );

    expect(service.maxProtocolVersion, 1);

    final session = service.createSession(
      protocolVersion: 1,
      channelId: '123456789012345678',
      selfUserId: '234567890123456789',
    );
    expect(session.protocolVersion, 1);

    session.reset();
    expect(session.protocolVersion, 0);
    session.dispose();
    session.dispose();
    expect(() => session.protocolVersion, throwsStateError);
  }, skip: !Platform.isWindows);

  test('rejects invalid DAVE session parameters before native calls', () {
    if (!Platform.isWindows) return;
    final service = NativeDaveService.open(
      libraryPath: 'windows/third_party/libdave/libdave.dll',
    );

    expect(
      () => service.createSession(
        protocolVersion: 2,
        channelId: '123',
        selfUserId: '456',
      ),
      throwsRangeError,
    );
    expect(
      () => service.createSession(
        protocolVersion: 1,
        channelId: 'not-a-snowflake',
        selfUserId: '456',
      ),
      throwsFormatException,
    );
  });

  test('owns native frame cryptors and passes media through explicitly', () {
    if (!Platform.isWindows) return;
    final service = NativeDaveService.open(
      libraryPath: 'windows/third_party/libdave/libdave.dll',
    );
    final encryptor = service.createEncryptor();
    final decryptor = service.createDecryptor();
    const frame = [
      13,
      197,
      174,
      221,
      91,
      220,
      63,
      32,
      190,
      86,
      151,
      229,
      77,
      209,
      244,
      55,
    ];

    expect(encryptor.hasKeyRatchet, isFalse);
    expect(encryptor.isPassthrough, isFalse);
    expect(
      () => encryptor.assignSsrcToCodec(-1, DaveMediaCodec.opus),
      throwsRangeError,
    );
    encryptor.assignSsrcToCodec(42, DaveMediaCodec.opus);
    expect(
      () => encryptor.encrypt(
        mediaType: DaveMediaType.audio,
        ssrc: 42,
        frame: frame,
      ),
      throwsA(
        isA<DaveFrameException>().having(
          (error) => error.failure,
          'failure',
          DaveFrameFailure.missingKeyRatchet,
        ),
      ),
    );

    encryptor.setPassthrough(true);
    decryptor.transitionToPassthrough(true);
    final encrypted = encryptor.encrypt(
      mediaType: DaveMediaType.audio,
      ssrc: 42,
      frame: frame,
    );
    final decrypted = decryptor.decrypt(
      mediaType: DaveMediaType.audio,
      encryptedFrame: encrypted,
    );

    expect(encrypted, frame);
    expect(decrypted, frame);

    encryptor.dispose();
    encryptor.dispose();
    decryptor.dispose();
    decryptor.dispose();
    expect(() => encryptor.isPassthrough, throwsStateError);
    expect(() => decryptor.transitionToPassthrough(false), throwsStateError);
  });
}
