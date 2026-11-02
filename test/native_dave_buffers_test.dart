import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flucord/src/data/dave/native_dave_buffers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('what comes out of native memory is bytes the native side cannot '
      'change later', () {
    final native = calloc<Uint8>(3);
    addTearDown(() => calloc.free(native));
    native.asTypedList(3).setAll(0, [1, 2, 3]);

    final Object copied = NativeDaveBuffers.copy(native, 3);
    native[0] = 9;

    expect(copied, isA<Uint8List>());
    expect(copied, [1, 2, 3]);
  });

  test('nothing to copy is empty bytes', () {
    final Object copied = NativeDaveBuffers.copy(nullptr, 0);

    expect(copied, isA<Uint8List>());
    expect(copied, isEmpty);
  });
}
