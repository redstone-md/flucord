import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/dave/native_dave_service.dart';

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
}
