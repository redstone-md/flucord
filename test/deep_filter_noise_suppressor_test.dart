import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flucord/src/data/audio/deep_filter_noise_suppressor.dart';
import 'package:flutter_test/flutter_test.dart';

const _library = 'windows/third_party/deepfilternet/df.dll';
const _model =
    'windows/third_party/deepfilternet/${DeepFilterNoiseSuppressor.modelFileName}';
const _sampleRate = 48000;
const _channels = 2;
const _frameSamples = 960;

void main() {
  // Windows only, and loudly: a missing DLL or model on a Windows checkout is
  // a broken bundle, not a reason to skip.
  final skip = !Platform.isWindows;

  Future<DeepFilterNoiseSuppressor> open() async {
    final suppressor = await DeepFilterNoiseSuppressor.open(
      libraryPath: _library,
      modelPath: _model,
    );
    addTearDown(suppressor.dispose);
    return suppressor;
  }

  test(
    'works in 10 ms hops and refuses a frame that is not whole hops',
    () async {
      final suppressor = await open();

      expect(suppressor.hopSize, 480);
      expect(
        () => suppressor.process(Int16List(1000), channels: _channels),
        throwsArgumentError,
      );
      suppressor.process(Int16List(_frameSamples * _channels), channels: 2);
      suppressor.dispose();
      suppressor.dispose();
      expect(
        () => suppressor.process(Int16List(_frameSamples * 2), channels: 2),
        throwsStateError,
      );
    },
    skip: skip,
  );

  test('drops the noise floor between words and keeps the words', () async {
    final suppressor = await open();
    final random = Random(7);
    // Synthesised speech (SAPI, 48 kHz mono) with white noise about 30 dB
    // under full scale laid over it, the way a fan sits under a voice.
    final clean = _readWav('test/fixtures/speech_48k.wav');
    final frames = clean.length ~/ _frameSamples;
    final noisy = Int16List(frames * _frameSamples * _channels);
    for (var i = 0; i < frames * _frameSamples; i++) {
      final noise = 0.02 * (random.nextDouble() * 2 - 1);
      final sample = (clean[i] + noise * 32767).round().clamp(-32768, 32767);
      noisy[i * _channels] = sample;
      noisy[i * _channels + 1] = sample;
    }

    final processed = Int16List.fromList(noisy);
    final stopwatch = Stopwatch();
    final micros = <int>[];
    for (var frame = 0; frame < frames; frame++) {
      final view = Int16List.sublistView(
        processed,
        frame * _frameSamples * _channels,
        (frame + 1) * _frameSamples * _channels,
      );
      stopwatch
        ..reset()
        ..start();
      suppressor.process(view, channels: _channels);
      stopwatch.stop();
      micros.add(stopwatch.elapsedMicroseconds);
    }

    // Frames are sorted by what the clean speech was doing in them: silent
    // ones held only noise, so what remains is what the filter let through;
    // loud ones must come out about as loud as they went in. The first half
    // second is the model settling and is left out.
    var quietIn = 0.0, quietOut = 0.0, voicedIn = 0.0, voicedOut = 0.0;
    var quietCount = 0, voicedCount = 0;
    for (
      var frame = _sampleRate ~/ _frameSamples ~/ 2;
      frame < frames;
      frame++
    ) {
      var cleanEnergy = 0.0, inEnergy = 0.0, outEnergy = 0.0;
      for (
        var i = frame * _frameSamples;
        i < (frame + 1) * _frameSamples;
        i++
      ) {
        final speech = clean[i] / 32768;
        final input = noisy[i * _channels] / 32768;
        final output = processed[i * _channels] / 32768;
        cleanEnergy += speech * speech;
        inEnergy += input * input;
        outEnergy += output * output;
      }
      final cleanRms = sqrt(cleanEnergy / _frameSamples);
      if (cleanRms < 0.001) {
        quietIn += inEnergy;
        quietOut += outEnergy;
        quietCount++;
      } else if (cleanRms > 0.05) {
        voicedIn += inEnergy;
        voicedOut += outEnergy;
        voicedCount++;
      }
    }
    expect(quietCount, greaterThan(10));
    expect(voicedCount, greaterThan(10));
    double db(double energy, int count) => 10 * log(energy / count) / ln10;
    final noiseDrop = db(quietIn, quietCount) - db(quietOut, quietCount);
    final voiceChange = db(voicedOut, voicedCount) - db(voicedIn, voicedCount);
    micros.sort();
    final median = micros[micros.length ~/ 2];
    final worst = micros.last;
    // ignore: avoid_print
    print(
      'deepfilternet: noise floor -${noiseDrop.toStringAsFixed(1)} dB, '
      'voiced ${voiceChange.toStringAsFixed(1)} dB, '
      '20 ms frame median ${median}us, worst ${worst}us',
    );

    expect(noiseDrop, greaterThan(10));
    expect(voiceChange, greaterThan(-3));
    // The timing is printed, not asserted: under the full suite's contention
    // the median has been measured above the 20 ms frame period, which says
    // nothing about the code. Read the figure from a run of this file alone.
  }, skip: skip);

  test('reports how late a sound comes out', () async {
    final suppressor = await open();
    // Half a second of silence, then a voice-like burst. The first output
    // sample above a tenth of the burst says how much delay the model adds
    // beyond the frame it is handed.
    const burstAt = _sampleRate ~/ 2;
    final signal = Int16List(_sampleRate * _channels);
    for (var i = burstAt; i < _sampleRate; i++) {
      final t = (i - burstAt) / _sampleRate;
      var voice = 0.0;
      for (var harmonic = 1; harmonic <= 25; harmonic++) {
        voice += sin(2 * pi * 150 * harmonic * t) / harmonic;
      }
      final sample = (0.25 * voice * 32767).round().clamp(-32768, 32767);
      signal[i * _channels] = sample;
      signal[i * _channels + 1] = sample;
    }
    for (var frame = 0; frame < _sampleRate ~/ _frameSamples; frame++) {
      suppressor.process(
        Int16List.sublistView(
          signal,
          frame * _frameSamples * _channels,
          (frame + 1) * _frameSamples * _channels,
        ),
        channels: _channels,
      );
    }
    var first = -1;
    for (var i = 0; i < _sampleRate; i++) {
      if (signal[i * _channels].abs() > 0.025 * 32767) {
        first = i;
        break;
      }
    }
    expect(first, greaterThanOrEqualTo(burstAt));
    final delayMs = (first - burstAt) * 1000 / _sampleRate;
    // ignore: avoid_print
    print('deepfilternet: onset delay ${delayMs.toStringAsFixed(1)} ms');
    expect(delayMs, lessThan(60));
  }, skip: skip);
  test(
    'a truncated model is refused rather than taking the process down',
    () async {
      final directory = await Directory.systemTemp.createTemp('flucord-dfn');
      addTearDown(() => directory.delete(recursive: true));
      final truncated = File('${directory.path}/model.tar.gz');
      await truncated.writeAsBytes(
        File(_model).readAsBytesSync().sublist(0, 4096),
      );

      await expectLater(
        DeepFilterNoiseSuppressor.open(
          libraryPath: _library,
          modelPath: truncated.path,
        ),
        throwsStateError,
      );
    },
    skip: skip,
  );
}

/// The samples of a 16-bit mono RIFF WAVE file.
Int16List _readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, offset, offset + 4);
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      return Int16List.sublistView(
        Uint8List.fromList(bytes.sublist(offset + 8, offset + 8 + size)),
      );
    }
    offset += 8 + size + (size & 1);
  }
  throw StateError('$path has no data chunk');
}
