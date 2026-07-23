import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_pcm_framer.dart';
import 'package:flucord/src/domain/voice_media.dart';

void main() {
  test('assembles arbitrary PCM chunks into exact 20ms stereo frames', () {
    final framer = VoicePcmFramer(
      sampleRate: 1000,
      channels: 2,
      samplesPerChannel: 2,
    );
    final bytes = Uint8List.fromList([
      1,
      0,
      0xff,
      0xff,
      0,
      0x80,
      0xff,
      0x7f,
      2,
      0,
    ]);

    expect(framer.add(_chunk(bytes.sublist(0, 4))), isEmpty);
    final frames = framer.add(_chunk(bytes.sublist(4)));

    expect(frames, hasLength(1));
    expect(frames.single, [1, -1, -32768, 32767]);
    expect(framer.pendingByteCount, 2);
  });

  test('rejects incompatible PCM and reset drops a partial frame', () {
    final framer = VoicePcmFramer();
    expect(
      () => framer.add(
        VoicePcmChunk(bytes: Uint8List(2), sampleRate: 44100, channels: 2),
      ),
      throwsStateError,
    );
    framer.add(
      VoicePcmChunk(bytes: Uint8List(2), sampleRate: 48000, channels: 2),
    );
    expect(framer.pendingByteCount, 2);
    framer.reset();
    expect(framer.pendingByteCount, 0);
  });
}

VoicePcmChunk _chunk(Uint8List bytes) =>
    VoicePcmChunk(bytes: bytes, sampleRate: 1000, channels: 2);
