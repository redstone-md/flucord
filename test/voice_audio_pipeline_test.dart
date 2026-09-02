import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_audio_pipeline.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/domain/voice_processing.dart';

import 'support/fake_voice_audio.dart';

void main() {
  test(
    'frames microphone PCM, encodes, and finishes speaking on disable',
    () async {
      final media = _FakeMediaService();
      final codecs = _FakeCodecFactory();
      final transport = _FakeAudioTransport();
      final pipeline = VoiceAudioPipeline(
        mediaService: media,
        codecFactory: codecs,
      );
      addTearDown(pipeline.dispose);
      addTearDown(media.dispose);

      await pipeline.bindTransport(transport);
      await pipeline.setEnabled(true);
      media.addPcm(Uint8List(1000));
      media.addPcm(Uint8List(2840));
      await _flushEvents();

      expect(codecs.encoder.inputs.single.length, 1920);
      expect(transport.sent, [
        Uint8List.fromList([1, 128]),
      ]);

      await pipeline.setEnabled(false);
      expect(transport.finishCount, 1);
    },
  );

  test('keeps independent Opus decoder state per remote user', () async {
    final media = _FakeMediaService();
    final codecs = _FakeCodecFactory();
    final transport = _FakeAudioTransport();
    final pipeline = VoiceAudioPipeline(
      mediaService: media,
      codecFactory: codecs,
    );
    addTearDown(pipeline.dispose);
    addTearDown(media.dispose);
    await pipeline.bindTransport(transport);
    final received = <VoiceRemotePcmFrame>[];
    final subscription = pipeline.remotePcm.listen(received.add);
    addTearDown(subscription.cancel);

    transport.addRemote('user-1', [5]);
    transport.addRemote('user-2', [7]);
    transport.addRemote('user-1', [9]);
    await _flushEvents();

    expect(codecs.decoders, hasLength(2));
    expect(received.map((frame) => frame.userId), [
      'user-1',
      'user-2',
      'user-1',
    ]);
    expect(received.map((frame) => frame.samples.single), [5, 7, 9]);
  });

  test('uses Opus PLC and FEC for bounded remote packet loss', () async {
    final media = _FakeMediaService();
    final codecs = _FakeCodecFactory();
    final transport = _FakeAudioTransport();
    final pipeline = VoiceAudioPipeline(
      mediaService: media,
      codecFactory: codecs,
    );
    addTearDown(pipeline.dispose);
    addTearDown(media.dispose);
    await pipeline.bindTransport(transport);
    final received = <VoiceRemotePcmFrame>[];
    final subscription = pipeline.remotePcm.listen(received.add);
    addTearDown(subscription.cancel);

    transport.addRemote('user-1', [9], missingFramesBefore: 3);
    await _flushEvents();

    expect(received.map((frame) => frame.samples.single), [-20, -20, -9, 9]);
  });

  test('resets per-user decoder after an unbounded packet gap', () async {
    final media = _FakeMediaService();
    final codecs = _FakeCodecFactory();
    final transport = _FakeAudioTransport();
    final pipeline = VoiceAudioPipeline(
      mediaService: media,
      codecFactory: codecs,
    );
    addTearDown(pipeline.dispose);
    addTearDown(media.dispose);
    await pipeline.bindTransport(transport);

    transport.addRemote('user-1', [1]);
    transport.addRemote('user-1', [2], missingFramesBefore: 20);
    await _flushEvents();

    expect(codecs.decoders, hasLength(2));
    expect(codecs.decoders.first.disposed, isTrue);
  });

  group('noise suppression', () {
    final samples = Int16List.fromList(
      List.generate(1920, (index) => (index * 37) % 2000 - 1000),
    );
    final bytes = samples.buffer.asUint8List();

    Future<(VoiceAudioPipeline, _FakeCodecFactory, List<Object>)> pump(
      _FakeMediaService media, {
      required Future<VoiceNoiseSuppressor> Function()? factory,
      required bool enabled,
      _FakeAudioTransport? transport,
    }) async {
      final codecs = _FakeCodecFactory();
      final pipeline = VoiceAudioPipeline(
        mediaService: media,
        codecFactory: codecs,
        noiseSuppressorFactory: factory,
      );
      addTearDown(pipeline.dispose);
      addTearDown(media.dispose);
      final errors = <Object>[];
      pipeline.errors.listen(errors.add);
      await pipeline.bindTransport(transport ?? _FakeAudioTransport());
      await pipeline.setEnabled(true);
      await pipeline.setNoiseSuppression(enabled);
      return (pipeline, codecs, errors);
    }

    test('passes microphone PCM through untouched while off', () async {
      final media = _FakeMediaService();
      var opened = 0;
      final (_, codecs, errors) = await pump(
        media,
        factory: () async {
          opened++;
          return FakeNoiseSuppressor();
        },
        enabled: false,
      );
      media.addPcm(bytes);
      await _flushEvents();

      expect(codecs.encoder.inputs.single, samples);
      expect(opened, 0);
      expect(errors, isEmpty);
    });

    test('runs every frame through one suppressor while on', () async {
      final media = _FakeMediaService();
      final suppressor = FakeNoiseSuppressor();
      var opened = 0;
      final (pipeline, codecs, _) = await pump(
        media,
        factory: () async {
          opened++;
          return suppressor;
        },
        enabled: true,
      );
      media.addPcm(bytes);
      media.addPcm(bytes);
      await _flushEvents();

      expect(opened, 1);
      expect(suppressor.frames, hasLength(2));
      expect(suppressor.channels, 2);
      expect(codecs.encoder.inputs.last, everyElement(0));

      await pipeline.dispose();
      expect(suppressor.disposed, isTrue);
    });

    test('frames pass raw while the model loads, then cleaned', () async {
      final media = _FakeMediaService();
      final loading = Completer<VoiceNoiseSuppressor>();
      final codecs = _FakeCodecFactory();
      final pipeline = VoiceAudioPipeline(
        mediaService: media,
        codecFactory: codecs,
        noiseSuppressorFactory: () => loading.future,
      );
      addTearDown(pipeline.dispose);
      addTearDown(media.dispose);
      await pipeline.bindTransport(_FakeAudioTransport());
      await pipeline.setEnabled(true);
      final opening = pipeline.setNoiseSuppression(true);

      media.addPcm(bytes);
      await _flushEvents();
      expect(pipeline.isNoiseSuppressionEnabled, isTrue);
      expect(codecs.encoder.inputs.single, samples);

      loading.complete(FakeNoiseSuppressor());
      await opening;
      media.addPcm(bytes);
      await _flushEvents();
      expect(codecs.encoder.inputs.last, everyElement(0));
    });

    test(
      'a suppressor that will not open turns the switch off, once',
      () async {
        final media = _FakeMediaService();
        var opened = 0;
        final (pipeline, codecs, errors) = await pump(
          media,
          factory: () async {
            opened++;
            throw StateError('df.dll is missing');
          },
          enabled: true,
        );
        media.addPcm(bytes);
        media.addPcm(bytes);
        await _flushEvents();

        expect(errors, hasLength(1));
        expect(pipeline.isNoiseSuppressionEnabled, isFalse);
        expect(pipeline.isNoiseSuppressionAvailable, isTrue);
        expect(codecs.encoder.inputs, hasLength(2));
        expect(codecs.encoder.inputs.first, samples);

        // Switching on again is the retry.
        await pipeline.setNoiseSuppression(true);
        await _flushEvents();
        expect(opened, 2);
        expect(errors, hasLength(2));
      },
    );

    test('a suppressor that throws mid-call is dropped and reported', () async {
      final media = _FakeMediaService();
      final suppressor = _BrokenSuppressor();
      final (pipeline, codecs, errors) = await pump(
        media,
        factory: () async => suppressor,
        enabled: true,
      );
      media.addPcm(bytes);
      media.addPcm(bytes);
      await _flushEvents();

      expect(errors, hasLength(1));
      expect(suppressor.disposed, isTrue);
      expect(pipeline.isNoiseSuppressionEnabled, isFalse);
      expect(codecs.encoder.inputs, hasLength(2));
      expect(codecs.encoder.inputs.last, samples);
    });

    test('going quiet flushes the model tail before finishing', () async {
      final media = _FakeMediaService();
      final transport = _FakeAudioTransport();
      final suppressor = FakeNoiseSuppressor();
      final (pipeline, codecs, _) = await pump(
        media,
        factory: () async => suppressor,
        enabled: true,
        transport: transport,
      );
      media.addPcm(bytes);
      await _flushEvents();

      await pipeline.setEnabled(false);

      // One frame of speech, then two of silence pushed through the model so
      // the last 29 ms of the word come out before the speaking burst ends.
      expect(suppressor.frames, hasLength(3));
      expect(suppressor.frames.last, everyElement(0));
      expect(transport.sent, hasLength(3));
      expect(transport.finishCount, 1);
      expect(codecs.encoder.inputs, hasLength(3));
    });

    test('a build without a suppressor says so', () async {
      final media = _FakeMediaService();
      final (pipeline, codecs, errors) = await pump(
        media,
        factory: null,
        enabled: true,
      );
      media.addPcm(bytes);
      await _flushEvents();

      expect(pipeline.isNoiseSuppressionAvailable, isFalse);
      expect(pipeline.isNoiseSuppressionEnabled, isFalse);
      expect(errors, isEmpty);
      expect(codecs.encoder.inputs.single, samples);
    });
  });
}

final class _BrokenSuppressor extends FakeNoiseSuppressor {
  @override
  void process(Int16List frame, {required int channels}) =>
      throw StateError('model failed');
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _FakeCodecFactory implements VoiceOpusCodecFactory {
  final _FakeEncoder encoder = _FakeEncoder();
  final List<_FakeDecoder> decoders = [];

  @override
  VoiceOpusEncoder createEncoder() => encoder;

  @override
  VoiceOpusDecoder createDecoder() {
    final decoder = _FakeDecoder();
    decoders.add(decoder);
    return decoder;
  }
}

final class _FakeEncoder implements VoiceOpusEncoder {
  final List<Int16List> inputs = [];

  @override
  Uint8List encode(Int16List pcm) {
    inputs.add(Int16List.fromList(pcm));
    return Uint8List.fromList([inputs.length, pcm.length ~/ 15]);
  }

  @override
  void dispose() {}
}

final class _FakeDecoder implements VoiceOpusDecoder {
  bool disposed = false;

  @override
  Int16List decode(Uint8List opusFrame) =>
      Int16List.fromList([opusFrame.first]);

  @override
  Int16List decodeFec(Uint8List opusFrame, {int frameDurationMs = 20}) =>
      Int16List.fromList([-opusFrame.first]);

  @override
  Int16List conceal({int frameDurationMs = 20}) =>
      Int16List.fromList([-frameDurationMs]);

  @override
  void dispose() => disposed = true;
}

final class _FakeAudioTransport implements VoiceAudioTransport {
  final StreamController<VoiceRemoteOpusFrame> _remote =
      StreamController.broadcast();
  final List<Uint8List> sent = [];
  int finishCount = 0;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _remote.stream;

  void addRemote(
    String userId,
    List<int> opus, {
    int missingFramesBefore = 0,
  }) => _remote.add(
    VoiceRemoteOpusFrame(
      userId: userId,
      opus: Uint8List.fromList(opus),
      missingFramesBefore: missingFramesBefore,
    ),
  );

  @override
  void sendOpusFrame(Uint8List opusFrame) =>
      sent.add(Uint8List.fromList(opusFrame));

  @override
  Future<void> finishSpeaking() async => finishCount++;
}

final class _FakeMediaService implements VoiceMediaService {
  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();

  void addPcm(Uint8List bytes) => _microphone.add(
    VoicePcmChunk(bytes: bytes, sampleRate: 48000, channels: 2),
  );

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphone.stream;
  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> selectAudioOutput(String deviceId) async {}
  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}
  @override
  Future<void> startMicrophone(String? deviceId) async {}
  @override
  Future<void> stopMicrophone() async {}
  @override
  Future<void> dispose() => _microphone.close();
}
