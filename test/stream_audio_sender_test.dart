import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_stream_audio_sender.dart';
import 'package:flucord/src/data/video/system_audio_capture.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('captured sound goes out as 20 ms stereo Opus frames', () {
    final sent = <Uint8List>[];
    final encoder = _FakeEncoder();
    final sender = DiscordStreamAudioSender(
      encoder: encoder,
      sendOpus: sent.add,
    );
    addTearDown(sender.stop);

    sender.accept(
      SystemAudioChunk(
        samples: Int16List(960 * 2),
        channels: 2,
        sampleRate: 48000,
      ),
    );

    expect(sent, hasLength(1));
    expect(sender.sentPackets, 1);
    // Stereo at 960 frames: 20 ms, which is what every Discord client sends.
    expect(encoder.encoded.single.length, 1920);
  });

  test('a mono endpoint is doubled, and a short block is held', () {
    var sends = 0;
    final sender = DiscordStreamAudioSender(
      encoder: _FakeEncoder(),
      sendOpus: (_) => sends++,
    );
    addTearDown(sender.stop);

    // WASAPI hands back whatever the endpoint had, which is not 20 ms.
    sender
      ..accept(_chunk(400))
      ..accept(_chunk(400));
    expect(sends, 0);

    sender.accept(_chunk(400));
    // 1200 frames: one out, 240 still held.
    expect(sends, 1);

    sender.accept(_chunk(720));
    expect(sends, 2);
  });

  test('a block with no channels describes nothing and is dropped', () {
    var sends = 0;
    final sender = DiscordStreamAudioSender(
      encoder: _FakeEncoder(),
      sendOpus: (_) => sends++,
    );
    addTearDown(sender.stop);

    sender.accept(
      SystemAudioChunk(samples: Int16List(960), channels: 0, sampleRate: 48000),
    );

    expect(sends, 0);
  });

  test('an endpoint at another rate is reported, not encoded wrong', () {
    var sends = 0;
    final sender = DiscordStreamAudioSender(
      encoder: _FakeEncoder(),
      sendOpus: (_) => sends++,
    );
    addTearDown(sender.stop);

    sender.accept(
      SystemAudioChunk(
        samples: Int16List(960 * 2),
        channels: 2,
        sampleRate: 44100,
      ),
    );

    expect(sends, 0);
    expect(sender.error, isA<StateError>());
  });

  test('an encoder that refuses a frame is reported, not thrown', () {
    final sender = DiscordStreamAudioSender(
      encoder: _FakeEncoder()..fail = true,
      sendOpus: (_) {},
    );
    addTearDown(sender.stop);

    // This runs from a capture callback: throwing would take the capture
    // stream down rather than losing one frame.
    sender.accept(_chunk(960));

    expect(sender.error, isA<StateError>());
    expect(sender.sentPackets, 0);
  });

  test('an empty encoding is not sent', () {
    var sends = 0;
    final sender = DiscordStreamAudioSender(
      encoder: _FakeEncoder()..empty = true,
      sendOpus: (_) => sends++,
    );
    addTearDown(sender.stop);

    sender.accept(_chunk(960));

    expect(sends, 0);
  });

  test('attaching follows the capture, and stopping lets go', () async {
    final chunks = StreamController<SystemAudioChunk>();
    var sends = 0;
    final sender = DiscordStreamAudioSender(
      encoder: _FakeEncoder(),
      sendOpus: (_) => sends++,
    );
    addTearDown(sender.stop);

    sender.attach(chunks.stream);
    chunks.add(_chunk(960));
    await Future<void>.delayed(Duration.zero);
    expect(sends, 1);

    sender.stop();
    chunks.add(_chunk(960));
    await Future<void>.delayed(Duration.zero);
    expect(sends, 1);
  });

  test('a failing capture is reported rather than left silent', () async {
    final chunks = StreamController<SystemAudioChunk>();
    final sender = DiscordStreamAudioSender(
      encoder: _FakeEncoder(),
      sendOpus: (_) {},
    );
    addTearDown(sender.stop);
    sender.attach(chunks.stream);

    chunks.addError(StateError('capture died'));
    await Future<void>.delayed(Duration.zero);

    expect(sender.error, isA<StateError>());
  });
}

SystemAudioChunk _chunk(int frames) => SystemAudioChunk(
  samples: Int16List(frames),
  channels: 1,
  sampleRate: 48000,
);

final class _FakeEncoder implements VoiceOpusEncoder {
  final List<Int16List> encoded = [];
  bool fail = false;
  bool empty = false;

  @override
  Uint8List encode(Int16List pcm) {
    if (fail) throw StateError('encoder refused the frame');
    encoded.add(pcm);
    return empty ? Uint8List(0) : Uint8List.fromList([1, 2, 3]);
  }

  @override
  void dispose() {}
}
