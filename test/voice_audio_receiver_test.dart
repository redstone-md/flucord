import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_audio_receiver.dart';
import 'package:flucord/src/domain/voice_audio.dart';

void main() {
  test('decodes remote Opus without an encoder or microphone', () async {
    final codecs = _FakeDecoderFactory();
    final transport = _FakeReceiverTransport();
    final receiver = VoiceAudioReceiver(decoderFactory: codecs);
    addTearDown(receiver.dispose);

    final received = <VoiceRemotePcmFrame>[];
    final subscription = receiver.remotePcm.listen(received.add);
    addTearDown(subscription.cancel);
    transport.onListen = () => transport.addRemote('participant-1', [7]);

    await receiver.bind(transport.remoteAudio);
    await _flushEvents();

    expect(codecs.decoderCreations, 1);
    expect(received.single.userId, 'participant-1');
    expect(received.single.samples, [7]);
  });

  test('keeps concealment and decoder state per remote sender', () async {
    final codecs = _FakeDecoderFactory();
    final transport = _FakeReceiverTransport();
    final receiver = VoiceAudioReceiver(decoderFactory: codecs);
    addTearDown(receiver.dispose);
    await receiver.bind(transport.remoteAudio);

    final received = <VoiceRemotePcmFrame>[];
    final subscription = receiver.remotePcm.listen(received.add);
    addTearDown(subscription.cancel);

    transport.addRemote('participant-1', [9], missingFramesBefore: 3);
    transport.addRemote('participant-2', [5]);
    await _flushEvents();

    expect(codecs.decoderCreations, 2);
    expect(received.map((frame) => frame.userId), [
      'participant-1',
      'participant-1',
      'participant-1',
      'participant-1',
      'participant-2',
    ]);
    expect(received.map((frame) => frame.samples.single), [-20, -20, -9, 9, 5]);
  });

  test('keeps only the latest transport during concurrent rebinds', () async {
    final receiver = VoiceAudioReceiver(decoderFactory: _FakeDecoderFactory());
    addTearDown(receiver.dispose);
    final received = <VoiceRemotePcmFrame>[];
    final subscription = receiver.remotePcm.listen(received.add);
    addTearDown(subscription.cancel);
    final first = _FakeReceiverTransport();
    final second = _FakeReceiverTransport();

    await Future.wait([
      receiver.bind(first.remoteAudio),
      receiver.bind(second.remoteAudio),
    ]);
    first.addRemote('participant-1', [1]);
    second.addRemote('participant-2', [2]);
    await _flushEvents();

    expect(received.map((frame) => frame.userId), ['participant-2']);
  });

  test('clears undecodable state when the transport changes', () async {
    final codecs = _FakeDecoderFactory()..failDecoding = true;
    final receiver = VoiceAudioReceiver(decoderFactory: codecs);
    addTearDown(receiver.dispose);
    final transport = _FakeReceiverTransport();
    final replacement = _FakeReceiverTransport();
    final errors = <Object>[];
    final errorSubscription = receiver.errors.listen(errors.add);
    addTearDown(errorSubscription.cancel);

    await receiver.bind(transport.remoteAudio);
    for (var index = 0; index < 49; index++) {
      transport.addRemote('participant-1', [index]);
    }
    await receiver.bind(replacement.remoteAudio);
    replacement.addRemote('participant-1', [50]);
    await _flushEvents();

    expect(errors, isEmpty);
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _FakeDecoderFactory implements VoiceOpusDecoderFactory {
  int decoderCreations = 0;
  bool failDecoding = false;

  @override
  VoiceOpusDecoder createDecoder() {
    decoderCreations++;
    return _FakeDecoder(this);
  }
}

final class _FakeDecoder implements VoiceOpusDecoder {
  _FakeDecoder(this._factory);

  final _FakeDecoderFactory _factory;

  @override
  Int16List decode(Uint8List opusFrame) {
    if (_factory.failDecoding) throw StateError('decode failed');
    return Int16List.fromList([opusFrame.first]);
  }

  @override
  Int16List decodeFec(Uint8List opusFrame, {int frameDurationMs = 20}) =>
      Int16List.fromList([-opusFrame.first]);

  @override
  Int16List conceal({int frameDurationMs = 20}) =>
      Int16List.fromList([-frameDurationMs]);

  @override
  void dispose() {}
}

/// A connection's audio, as the stream a receiver is bound to.
final class _FakeReceiverTransport {
  _FakeReceiverTransport() {
    _remote = StreamController.broadcast(onListen: () => onListen?.call());
  }

  late final StreamController<VoiceRemoteOpusFrame> _remote;
  void Function()? onListen;

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
