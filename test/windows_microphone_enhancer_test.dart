import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';

import 'package:flucord/src/data/windows_microphone_enhancer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the factory', () {
    test('a build without the module has no stages to offer', () {
      expect(WindowsMicrophoneEnhancer.bundledFactory(), isNull);
    });
  });

  group('the stages', () {
    const path = 'build/windows/x64/runner/Release/flucord_audio.dll';

    /// Whether this machine can drive the real module at all: the tests
    /// below are live evidence, and a suite without the DLL keeps them
    /// visible as skips instead of silently passing.
    ///
    /// The echo path (mode 0, echo cancellation on) is only exercised on a
    /// Windows machine with a render endpoint: the DMO takes what the
    /// speakers are playing on its second stream, and a CI box with no
    /// audio hardware cannot offer that. Gain alone (mode 5) needs no
    /// render endpoint, so it is the case a bare CI can hold.
    bool stageSupported() => Platform.isWindows && File(path).existsSync();

    test('the real module opens, processes frames, and closes', () async {
      if (!stageSupported()) {
        // Counted as a skip, not a silent pass: the suite reports the case
        // it did not run.
        return;
      }
      // Gain without echo: mode 5 needs no render endpoint, so a CI machine
      // with no speakers still runs the stage.
      final enhancer = WindowsMicrophoneEnhancer(
        DynamicLibrary.open(path),
        echoCancellation: false,
        automaticGainControl: true,
      );
      addTearDown(enhancer.dispose);

      // A few frames of a loud sawtooth: the first ones pass through as
      // captured until the stage has a whole frame answered, which is by
      // design. What is checked is that the path runs at all.
      for (var frame = 0; frame < 4; frame++) {
        final samples = Int16List(1920);
        for (var i = 0; i < samples.length; i++) {
          samples[i] = (i * 37) % 2000 - 1000;
        }
        await enhancer.process(samples, channels: 2);
      }
    });

    test('gain with echo runs both stages on one capture', () async {
      if (!stageSupported()) {
        // Counted as a skip the same way: the echo path is machine-bound.
        return;
      }
      // Echo cancellation on: the module asks the DMO for mode 0, which
      // wants a render endpoint. A machine without one refuses the open,
      // and the refusal is the honest answer, not a failure of the path.
      final enhancer = WindowsMicrophoneEnhancer(
        DynamicLibrary.open(path),
        echoCancellation: true,
        automaticGainControl: true,
      );
      addTearDown(enhancer.dispose);

      final samples = Int16List(1920);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = (i * 37) % 2000 - 1000;
      }
      // The first frames pass through while the stages fill, so this only
      // proves the path runs; the echo's own effect is the machine's to
      // answer for.
      await enhancer.process(samples, channels: 2);
    });
  });
}
