import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';

import 'package:flucord/src/data/video/system_audio_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what a block says', () {
    test('a frame is one sample per channel, not one sample', () {
      final chunk = SystemAudioChunk(
        samples: Int16List(0),
        channels: 2,
        sampleRate: 48000,
      );

      expect(chunk.frameCount, 0);
      expect(
        SystemAudioChunk(
          samples: Int16List.fromList([1, 2, 3, 4, 5, 6]),
          channels: 2,
          sampleRate: 48000,
        ).frameCount,
        3,
      );
      // A block that claims no channels describes nothing, and dividing by it
      // would be worse than answering zero.
      expect(
        SystemAudioChunk(
          samples: Int16List.fromList([1, 2]),
          channels: 0,
          sampleRate: 48000,
        ).frameCount,
        0,
      );
    });

    test('any width becomes stereo: mono doubled, wider trimmed', () {
      expect(toStereo(Int16List.fromList([1, 2, 3]), 1), [1, 1, 2, 2, 3, 3]);
      // 5.1: the front pair stays, the rest is dropped.
      expect(
        toStereo(
          Int16List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
          6,
        ),
        [1, 2, 7, 8],
      );
      // Stereo is handed straight back rather than copied.
      final stereo = Int16List.fromList([1, 2, 3, 4]);
      expect(identical(toStereo(stereo, 2), stereo), isTrue);
    });
  });

  group('the capture', () {
    test('a build with no module never claims to be recording', () async {
      const capture = UnavailableSystemAudioCapture();

      expect(capture.isSupported, isFalse);
      expect(capture.isRunning, isFalse);
      expect(await capture.start(), isFalse);
      expect(capture.chunks, emitsDone);
      await capture.stop();
    });

    test('a Windows capture without the module says the same', () async {
      final capture = WindowsSystemAudioCapture.withLibrary(null);

      expect(capture.isSupported, isFalse);
      expect(await capture.start(), isFalse);
      expect(capture.isRunning, isFalse);
      await capture.stop();
      await capture.close();
    });

    test('the real endpoint opens, produces blocks, and closes', () async {
      const path = 'build/windows/x64/runner/Release/flucord_audio.dll';
      if (!Platform.isWindows || !File(path).existsSync()) return;
      final capture = WindowsSystemAudioCapture.withLibrary(
        DynamicLibrary.open(path),
      );
      addTearDown(capture.close);

      expect(capture.isSupported, isTrue);
      if (!await capture.start()) {
        // A machine with no output device has nothing to capture, and the
        // service says so rather than promising silence as sound.
        expect(capture.isRunning, isFalse);
        return;
      }
      expect(capture.isRunning, isTrue);
      // Asked twice is the same capture, not a second endpoint.
      expect(await capture.start(), isTrue);

      final blocks = <SystemAudioChunk>[];
      final subscription = capture.chunks.listen(blocks.add);
      // Silence still produces blocks: WASAPI reports the silent flag rather
      // than stopping, which is what keeps a share's audio alive between two
      // sounds.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await subscription.cancel();

      // Whether this Windows can leave the app's own sound out (build 20348
      // and later). When it can, the capture asks for the transport's format
      // directly and every block is 48 kHz stereo.
      final excludesOwnSound = capture.excludesOwnSound;
      printOnFailure('excludes own sound: $excludesOwnSound');
      await capture.stop();
      expect(capture.isRunning, isFalse);
      expect(capture.excludesOwnSound, isFalse);
      for (final block in blocks) {
        expect(block.channels, greaterThan(0));
        expect(block.sampleRate, greaterThan(0));
        expect(block.samples.length, block.frameCount * block.channels);
        if (excludesOwnSound) {
          expect(block.channels, 2);
          expect(block.sampleRate, 48000);
        }
      }
    });
  });
}
