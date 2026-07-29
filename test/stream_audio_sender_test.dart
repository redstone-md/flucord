import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_stream_audio_sender.dart';
import 'package:flucord/src/data/video/system_audio_capture.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('captured sound goes out on the stream SSRC, not the voice one', () {
    final sent = <DiscordRtpFrame>[];
    final encoder = _FakeEncoder();
    final sender = DiscordStreamAudioSender(
      ssrc: 4242,
      sink: (frame) {
        sent.add(frame);
        return frame.payload.length;
      },
      encoder: encoder,
    );
    addTearDown(sender.stop);

    // Two channels of 960 frames: one Opus frame's worth after the downmix.
    sender.accept(
      SystemAudioChunk(
        samples: Int16List(960 * 2),
        channels: 2,
        sampleRate: 48000,
      ),
    );

    expect(sent.single.header.ssrc, 4242);
    expect(sender.sentPackets, 1);
    // Mono at 960 samples: 20 ms, which is what every Discord client sends.
    expect(encoder.encoded.single.length, 960);
  });

  test('a block that is not a whole frame is held rather than sent short', () {
    final sent = <DiscordRtpFrame>[];
    final sender = DiscordStreamAudioSender(
      ssrc: 1,
      sink: (frame) {
        sent.add(frame);
        return 1;
      },
      encoder: _FakeEncoder(),
    );
    addTearDown(sender.stop);

    // WASAPI hands back whatever the endpoint had, which is not 20 ms.
    sender
      ..accept(_chunk(400))
      ..accept(_chunk(400));
    expect(sent, isEmpty);

    sender.accept(_chunk(400));
    // 1200 samples: one frame out, 240 still held.
    expect(sent, hasLength(1));

    sender.accept(_chunk(720));
    expect(sent, hasLength(2));
  });

  test('a block with no channels describes nothing and is dropped', () {
    var sends = 0;
    final sender = DiscordStreamAudioSender(
      ssrc: 1,
      sink: (_) {
        sends++;
        return 1;
      },
      encoder: _FakeEncoder(),
    );
    addTearDown(sender.stop);

    sender.accept(
      SystemAudioChunk(
        samples: Int16List(960),
        channels: 0,
        sampleRate: 48000,
      ),
    );

    expect(sends, 0);
  });

  test('an encoder that refuses a frame is reported, not thrown', () {
    final sender = DiscordStreamAudioSender(
      ssrc: 1,
      sink: (_) => 1,
      encoder: _FakeEncoder()..fail = true,
    );
    addTearDown(sender.stop);

    // This runs from a capture callback: throwing would take the capture
    // stream down rather than losing one frame.
    sender.accept(_chunk(960));

    expect(sender.error, isA<StateError>());
    expect(sender.sentPackets, 0);
  });

  test('an empty encoding is not put on the wire', () {
    var sends = 0;
    final sender = DiscordStreamAudioSender(
      ssrc: 1,
      sink: (_) {
        sends++;
        return 1;
      },
      encoder: _FakeEncoder()..empty = true,
    );
    addTearDown(sender.stop);

    sender.accept(_chunk(960));

    expect(sends, 0);
  });

  test('attaching follows the capture, and stopping lets go', () async {
    final chunks = StreamController<SystemAudioChunk>();
    var sends = 0;
    final sender = DiscordStreamAudioSender(
      ssrc: 7,
      sink: (_) {
        sends++;
        return 1;
      },
      encoder: _FakeEncoder(),
    );
    addTearDown(sender.stop);

    sender.attach(chunks.stream);
    chunks.add(_chunk(960));
    await Future<void>.delayed(Duration.zero);
    expect(sends, 1);
    expect(sender.ssrc, 7);

    sender.stop();
    chunks.add(_chunk(960));
    await Future<void>.delayed(Duration.zero);
    expect(sends, 1);
  });

  test('a failing capture is reported rather than left silent', () async {
    final chunks = StreamController<SystemAudioChunk>();
    final sender = DiscordStreamAudioSender(
      ssrc: 1,
      sink: (_) => 1,
      encoder: _FakeEncoder(),
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
