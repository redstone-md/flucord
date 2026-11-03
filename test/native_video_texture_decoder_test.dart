import 'dart:async';

import 'package:flucord/src/data/video/native_video_decoder_service.dart';
import 'package:flucord/src/data/video/native_video_textures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A module that exists nowhere, so the decoder's open fails the way it does
/// on a machine without the native module.
const _missingModule = 'flucord_video_missing_module.dll';

/// Textures handed out by a test, which says when each one is ready.
final class _Textures implements NativeVideoTextures {
  _Textures({this.refuse = false});

  final bool refuse;
  final List<int> disposed = [];
  Completer<NativeVideoTexture>? pending;
  var _next = 7;

  @override
  Future<NativeVideoTexture> create() {
    if (refuse) {
      return Future.error(PlatformException(code: 'unavailable'));
    }
    final made = (id: _next++, surface: 0x1000);
    final gate = pending;
    if (gate == null) return Future.value(made);
    return gate.future.then((_) => made);
  }

  @override
  Future<void> dispose(int id) async => disposed.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a decoder that will not open gives its texture back', () async {
    final textures = _Textures();
    final decoder = NativeVideoTextureDecoder(
      libraryPath: _missingModule,
      textures: textures,
    );

    await expectLater(decoder.start(), throwsStateError);
    expect(textures.disposed, [7]);

    // Nothing is left to stop.
    await decoder.stop();
    expect(textures.disposed, [7]);
  });

  test('a texture the runner refuses is the start failing', () async {
    final textures = _Textures(refuse: true);
    final decoder = NativeVideoTextureDecoder(
      libraryPath: _missingModule,
      textures: textures,
    );

    await expectLater(decoder.start(), throwsA(isA<PlatformException>()));
    await decoder.stop();
    expect(textures.disposed, isEmpty);
  });

  test('a stop while the texture is being made gives it back once it is '
      'made', () async {
    final textures = _Textures()..pending = Completer();
    final decoder = NativeVideoTextureDecoder(
      libraryPath: _missingModule,
      textures: textures,
    );

    final starting = decoder.start();
    await decoder.stop();
    textures.pending!.complete((id: 0, surface: 0));
    await starting;

    expect(textures.disposed, [7]);
  });
}
