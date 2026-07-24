import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_voice_message_recorder.dart';
import 'package:flucord/src/data/voice_message_pcm_capture.dart';
import 'package:flucord/src/domain/voice_audio.dart';

void main() {
  test('records PCM into owned Ogg/Opus voice-message metadata', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-voice-recorder-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final capture = _FakeCapture();
    final codecs = _FakeCodecFactory();
    final recorder = NativeVoiceMessageRecorder(
      codecs,
      capture: capture,
      clock: () => DateTime.utc(2026, 7, 24, 8),
      directoryProvider: () async => directory,
    );
    addTearDown(recorder.dispose);
    final progress = <Duration>[];
    final subscription = recorder.progress.listen(
      (event) => progress.add(event.duration),
    );
    addTearDown(subscription.cancel);

    await recorder.start();
    capture.add(_pcmFrames(5, amplitude: 16384));
    await Future<void>.delayed(Duration.zero);
    final pending = await recorder.stop();

    expect(pending.durationSecs, 0.1);
    expect(base64Decode(pending.waveform), hasLength(1));
    expect(base64Decode(pending.waveform).single, greaterThan(1));
    expect(progress, contains(const Duration(milliseconds: 100)));
    expect(codecs.encoder.inputs, hasLength(5));
    expect(codecs.encoder.disposed, isTrue);
    final file = File(pending.path);
    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(ascii.decode(bytes.sublist(0, 4)), 'OggS');
    expect(bytes, containsAllInOrder(ascii.encode('OpusHead')));

    await recorder.delete(pending);
    expect(await file.exists(), isFalse);
  });

  test('cancel discards an active recording without creating a file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-voice-cancel-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final capture = _FakeCapture();
    final codecs = _FakeCodecFactory();
    final recorder = NativeVoiceMessageRecorder(
      codecs,
      capture: capture,
      directoryProvider: () async => directory,
    );
    addTearDown(recorder.dispose);

    await recorder.start();
    capture.add(_pcmFrames(1, amplitude: 1000));
    await recorder.cancel();

    expect(recorder.isRecording, isFalse);
    expect(codecs.encoder.disposed, isTrue);
    expect(directory.listSync(), isEmpty);
  });

  test('start failure restores an idle reusable lifecycle', () async {
    final failure = StateError('capture failed to start');
    final capture = _FakeCapture(startError: failure);
    final codecs = _FakeCodecFactory();
    final recorder = NativeVoiceMessageRecorder(codecs, capture: capture);
    addTearDown(recorder.dispose);

    await expectLater(recorder.start(), throwsA(same(failure)));

    expect(recorder.isRecording, isFalse);
    expect(codecs.encoder.disposed, isTrue);
  });

  test('stop failure still releases the active session', () async {
    final failure = StateError('capture failed to stop');
    final capture = _FakeCapture(stopError: failure);
    final codecs = _FakeCodecFactory();
    final recorder = NativeVoiceMessageRecorder(codecs, capture: capture);
    addTearDown(recorder.dispose);

    await recorder.start();
    await expectLater(recorder.stop(), throwsA(same(failure)));

    expect(recorder.isRecording, isFalse);
    expect(codecs.encoder.disposed, isTrue);
  });

  test('cancel failure still releases the active session', () async {
    final failure = StateError('capture failed to cancel');
    final capture = _FakeCapture(cancelError: failure);
    final codecs = _FakeCodecFactory();
    final recorder = NativeVoiceMessageRecorder(codecs, capture: capture);
    addTearDown(recorder.dispose);

    await recorder.start();
    await expectLater(recorder.cancel(), throwsA(same(failure)));

    expect(recorder.isRecording, isFalse);
    expect(codecs.encoder.disposed, isTrue);
  });
}

Uint8List _pcmFrames(int count, {required int amplitude}) {
  final samples = Int16List(count * 1920);
  for (var index = 0; index < samples.length; index++) {
    samples[index] = index.isEven ? amplitude : -amplitude;
  }
  return Uint8List.view(samples.buffer);
}

final class _FakeCapture implements VoiceMessagePcmCapture {
  _FakeCapture({this.startError, this.stopError, this.cancelError});

  final StreamController<Uint8List> _controller = StreamController.broadcast();
  final Object? startError;
  final Object? stopError;
  final Object? cancelError;

  void add(Uint8List bytes) => _controller.add(bytes);

  @override
  Future<Stream<Uint8List>> start() async {
    if (startError case final error?) throw error;
    return _controller.stream;
  }

  @override
  Future<void> stop() async {
    if (stopError case final error?) throw error;
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  Future<void> cancel() async {
    if (cancelError case final error?) throw error;
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

final class _FakeCodecFactory implements VoiceOpusCodecFactory {
  final _FakeEncoder encoder = _FakeEncoder();

  @override
  VoiceOpusEncoder createEncoder() => encoder;

  @override
  VoiceOpusDecoder createDecoder() => throw UnimplementedError();
}

final class _FakeEncoder implements VoiceOpusEncoder {
  final List<Int16List> inputs = [];
  bool disposed = false;

  @override
  Uint8List encode(Int16List pcm) {
    inputs.add(Int16List.fromList(pcm));
    return Uint8List.fromList([inputs.length, 0x7f]);
  }

  @override
  void dispose() => disposed = true;
}
