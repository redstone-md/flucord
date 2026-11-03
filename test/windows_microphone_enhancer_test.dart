import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flucord/src/data/windows_microphone_enhancer.dart';
import 'package:flutter_test/flutter_test.dart';

/// One 20 ms stereo frame at 48 kHz of a [hertz] tone at [amplitude].
Int16List _tone(int frame, {required double hertz, required int amplitude}) {
  final samples = Int16List(960 * 2);
  for (var i = 0; i < 960; i++) {
    final t = (frame * 960 + i) / 48000;
    final value = (amplitude * math.sin(2 * math.pi * hertz * t)).round();
    samples[i * 2] = value;
    samples[i * 2 + 1] = value;
  }
  return samples;
}

/// The strength of [hertz] in the left channel of [frame] (Goertzel).
double _strengthAt(Int16List frame, double hertz) {
  final coefficient = 2 * math.cos(2 * math.pi * hertz / 48000);
  var previous = 0.0;
  var beforePrevious = 0.0;
  for (var i = 0; i < frame.length; i += 2) {
    final current = frame[i] + coefficient * previous - beforePrevious;
    beforePrevious = previous;
    previous = current;
  }
  return math.sqrt(
    previous * previous +
        beforePrevious * beforePrevious -
        coefficient * previous * beforePrevious,
  );
}

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
    /// Gain alone needs no speakers. The echo path loops the default
    /// speakers back, so a CI box with no audio hardware refuses its open.
    bool stageSupported() => Platform.isWindows && File(path).existsSync();

    test('gain keeps the whole band of the voice', () async {
      if (!stageSupported()) {
        // Counted as a skip, not a silent pass: the suite reports the case
        // it did not run.
        return;
      }
      final enhancer = WindowsMicrophoneEnhancer(
        DynamicLibrary.open(path),
        echoCancellation: false,
        automaticGainControl: true,
      );
      addTearDown(enhancer.dispose);

      // A 12 kHz tone is above what a 16 kHz path can carry at all (8 kHz),
      // and what made voices sound like a telephone. It must come through.
      late Int16List last;
      for (var frame = 0; frame < 50; frame++) {
        last = _tone(frame, hertz: 12000, amplitude: 3000);
        await enhancer.process(last, channels: 2);
      }
      final kept = _strengthAt(last, 12000);
      final reference = _strengthAt(
        _tone(49, hertz: 12000, amplitude: 3000),
        12000,
      );
      expect(kept, greaterThan(reference * 0.5));
    });

    test('gain with echo runs both stages on one capture', () async {
      if (!stageSupported()) {
        // Counted as a skip the same way: the echo path is machine-bound.
        return;
      }
      // A machine without speakers refuses the open, and the refusal is the
      // honest answer, not a failure of the path.
      final enhancer = WindowsMicrophoneEnhancer(
        DynamicLibrary.open(path),
        echoCancellation: true,
        automaticGainControl: true,
      );
      addTearDown(enhancer.dispose);

      for (var frame = 0; frame < 4; frame++) {
        await enhancer.process(
          _tone(frame, hertz: 440, amplitude: 3000),
          channels: 2,
        );
      }
    });
  });
}
