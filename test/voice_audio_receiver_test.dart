import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_audio_receiver.dart';
import 'package:flucord/src/domain/voice_audio.dart';

void main() {
  test('decodes remote Opus without creating or reading a microphone', () async {
    final codecs = _FakeDecoderFactory();
    final transport = _FakeReceiverTransport();
    final receiver = VoiceAudioReceiver(
      decoderFactory: codecs,
      transport: transport,
    );
    addTearDown(receiver.dispose);

    final received = <VoiceRemotePcmFrame>[];
    final subscription = receiver.remotePcm.listen(received.add);
    addTearDown(subscription.cancel);

    transport.addRemote('user-1', [7]);
    await _flushEvents();

    expect(codecs.decoderCreations, 1);
    expect(received.single.userId, 'user-1');
    expect(received.single.samples, [7]);
  });

  test('keeps concealment and decoder state per remote sender', () async {
    final codecs = _FakeDecoderFactory();
    final transport = _FakeReceiverTransport();
    final receiver = VoiceAudioReceiver(decoderFactory: codecs);
    addTearDown(receiver.dispose);
    await receiver.bindTransport(transport);

    final received = <VoiceRemotePcmFrame>[];
    final subscription = receiver.remotePcm.listen(received.add);
    addTearDown(subscription.cancel);

    transport.addRemote('user-1', [9], missingFramesBefore: 3);
    transport.addRemote('user-2', [5]);
    await _flushEvents();

    expect(codecs.decoderCreations, 2);
    expect(received.map((frame) => frame.userId), [
      'user-1',
      'user-1',
      'user-1',
      'user-1',
      'user-2',
    ]);
    expect(received.map((frame) => frame.samples.single), [-20, -20, -9, 9, 5]);
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _FakeDecoderFactory implements VoiceOpusDecoderFactory {
  int decoderCreations = 0;

  @override
  VoiceOpusDecoder createDecoder() {
    decoderCreations++;
    return _FakeDecoder();
  }
}

final class _FakeDecoder implements VoiceOpusDecoder {
  @override
  Int16List decode(Uint8List opusFrame) => Int16List.fromList([opusFrame.first]);

  @override
  Int16List decodeFec(Uint8List opusFrame, {int frameDurationMs = 20}) =>
      Int16List.fromList([-opusFrame.first]);

  @override
  Int16List conceal({int frameDurationMs = 20}) =>
      Int16List.fromList([-frameDurationMs]);

  @override
  void dispose() {}
}

final class _FakeReceiverTransport implements VoiceAudioReceiverTransport {
  final StreamController<VoiceRemoteOpusFrame> _remote =
      StreamController.broadcast();

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
}
