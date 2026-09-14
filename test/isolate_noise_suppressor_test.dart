import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flucord/src/data/audio/isolate_noise_suppressor.dart';
import 'package:flucord/src/domain/voice_processing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cleans a frame across the round trip, in place', () async {
    final suppressor = await IsolateNoiseSuppressor.open(
      loader: _openCountingSuppressor,
      recipe: {},
    );
    addTearDown(suppressor.dispose);

    expect(suppressor.hopSize, _hopSize);
    final frame = Int16List.fromList([10, 20, 30, 40]);
    await suppressor.process(frame, channels: 2);
    expect(frame, [11, 21, 31, 41]);
  });

  test('tells the model it is going away, and it goes', () async {
    final gone = ReceivePort();
    addTearDown(gone.close);
    final suppressor = await IsolateNoiseSuppressor.open(
      loader: _openCountingSuppressor,
      recipe: {'onDispose': gone.sendPort},
    );
    suppressor.dispose();

    expect(gone.first.timeout(_wait), completes);
  });

  test('a model that will not open says why', () async {
    await expectLater(
      IsolateNoiseSuppressor.open(loader: _openBrokenSuppressor, recipe: {}),
      throwsStateError,
    );
  });

  test('a worker that dies fails the frame it was cleaning', () async {
    final suppressor = await IsolateNoiseSuppressor.open(
      loader: _openSuicidalSuppressor,
      recipe: {},
    );
    addTearDown(suppressor.dispose);

    await expectLater(
      suppressor.process(Int16List(_hopSize * 2), channels: 2),
      throwsStateError,
    );
  });
}

/// Long enough for an isolate to answer, short enough that a hung test is
/// still noticed.
const _wait = Duration(seconds: 10);

const _hopSize = 2;

/// A model stand-in: every sample comes back one louder, and the worker says
/// when it was told to go away. Top level, because the loader crosses to the
/// worker as a tear-off.
Future<VoiceNoiseSuppressor> _openCountingSuppressor(
  Map<String, Object?> recipe,
) async {
  final onDispose = recipe['onDispose'] as SendPort?;
  return _CountingSuppressor(onDispose);
}

Future<VoiceNoiseSuppressor> _openBrokenSuppressor(
  Map<String, Object?> recipe,
) async => throw StateError('df.dll is missing');

Future<VoiceNoiseSuppressor> _openSuicidalSuppressor(
  Map<String, Object?> recipe,
) async => _SuicidalSuppressor();

final class _CountingSuppressor implements VoiceNoiseSuppressor {
  _CountingSuppressor(this._onDispose);

  final SendPort? _onDispose;

  @override
  int get hopSize => _hopSize;

  @override
  Future<void> process(Int16List frame, {required int channels}) async {
    for (var index = 0; index < frame.length; index++) {
      frame[index] += 1;
    }
  }

  @override
  void dispose() => _onDispose?.send('disposed');
}

/// A model that takes the isolate with it mid-frame: its work never
/// finishes, and no answer is ever sent. Terminated before the next event,
/// which is the case an exit listener is still told about.
final class _SuicidalSuppressor implements VoiceNoiseSuppressor {
  @override
  int get hopSize => _hopSize;

  @override
  Future<void> process(Int16List frame, {required int channels}) {
    Isolate.current.kill(priority: Isolate.beforeNextEvent);
    return Completer<void>().future;
  }

  @override
  void dispose() {}
}
