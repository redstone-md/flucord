import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_audio_pipeline.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_media.dart';

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
  Object? get previewRenderer => null;
  @override
  Stream<void> get screenShareEnded => const Stream.empty();
  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async => const [];
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
  Future<void> startScreenShare(String sourceId) async {}
  @override
  Future<void> stopMicrophone() async {}
  @override
  Future<void> stopScreenShare() async {}
  @override
  Future<void> dispose() => _microphone.close();
}
