import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_video_stream_transport.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _accessUnit({int sliceLength = 8}) => Uint8List.fromList([
  0,
  0,
  0,
  1,
  0x67,
  0x42,
  0x00,
  0,
  0,
  1,
  0x65,
  ...List.filled(sliceLength, 0xaa),
]);

EncodedVideoFrame _frame({
  int sliceLength = 8,
  Duration timestamp = Duration.zero,
  bool isKeyframe = false,
}) => EncodedVideoFrame(
  bytes: _accessUnit(sliceLength: sliceLength),
  timestamp: timestamp,
  isKeyframe: isKeyframe,
);

void main() {
  group('pacing', _pacingTests);

  test('builds an RTP header for every payload of a picture', () {
    final sent = <DiscordRtpFrame>[];
    final transport = DiscordVideoStreamTransport(
      ssrc: 0x1234,
      sink: (frame) {
        sent.add(frame);
        return frame.payload.length;
      },
    );

    final count = transport.send(
      _frame(timestamp: const Duration(milliseconds: 100), isKeyframe: true),
    );

    expect(count, 2);
    expect(sent.length, 2);
    expect(sent.every((frame) => frame.header.ssrc == 0x1234), isTrue);
    // Video takes its own payload type: a stream reusing the voice one would
    // be decoded as Opus and thrown away.
    expect(
      sent.every(
        (frame) =>
            frame.header.payloadType ==
            DiscordRtpHeader.discordVideoPayloadType,
      ),
      isTrue,
    );
    expect(sent.map((frame) => frame.header.sequence), [0, 1]);
    expect(sent.map((frame) => frame.header.timestamp).toSet().length, 1);
    expect(sent.first.header.marker, isFalse);
    expect(sent.last.header.marker, isTrue);
    expect(transport.sentPackets, 2);
    expect(transport.sentBytes, greaterThan(0));
    expect(transport.ssrc, 0x1234);
  });

  test('a large picture is fragmented across packets', () {
    var count = 0;
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      sink: (frame) {
        count++;
        return 0;
      },
      maxPayloadSize: 100,
    );

    transport.send(_frame(sliceLength: 500));

    expect(count, greaterThan(5));
    expect(transport.sentPackets, count);
  });

  test('the RTP clock keeps going forward across an encoder restart', () {
    final sent = <DiscordRtpFrame>[];
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      sink: (frame) {
        sent.add(frame);
        return 0;
      },
    );

    transport.send(_frame(timestamp: const Duration(seconds: 10)));
    // A restarted encoder counts from zero again.
    transport.send(_frame(timestamp: Duration.zero));
    transport.send(_frame(timestamp: const Duration(milliseconds: 33)));

    final stamps = sent.map((frame) => frame.header.timestamp).toSet().toList();
    expect(stamps, hasLength(3));
    expect(stamps[1], greaterThan(stamps[0]));
    expect(stamps[2], greaterThan(stamps[1]));
    // One frame on, at 90 kHz: 33 ms is 2970 ticks.
    expect(stamps[1] - stamps[0], 2970);
  });

  test('an empty picture sends nothing', () {
    var count = 0;
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      sink: (frame) {
        count++;
        return 0;
      },
    );

    final sent = transport.send(
      EncodedVideoFrame(
        bytes: Uint8List(0),
        timestamp: Duration.zero,
        isKeyframe: false,
      ),
    );

    expect(sent, 0);
    expect(count, 0);
  });

  test('a stream of frames is sent as it arrives', () async {
    final frames = StreamController<EncodedVideoFrame>();
    addTearDown(frames.close);
    var count = 0;
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      sink: (frame) {
        count++;
        return 0;
      },
    )..attach(frames.stream);

    frames
      ..add(_frame())
      ..add(_frame(timestamp: const Duration(milliseconds: 33)));
    await Future<void>.delayed(Duration.zero);

    expect(count, 4);
    expect(transport.sentPackets, 4);

    await transport.stop();
    frames.add(_frame());
    await Future<void>.delayed(Duration.zero);
    // Stopping detaches: nothing further goes out.
    expect(transport.sentPackets, 4);
  });

  test('attaching twice drops the first stream', () async {
    final first = StreamController<EncodedVideoFrame>();
    final second = StreamController<EncodedVideoFrame>();
    addTearDown(first.close);
    addTearDown(second.close);
    var count = 0;
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      sink: (frame) {
        count++;
        return 0;
      },
    )..attach(first.stream);

    transport.attach(second.stream);
    first.add(_frame());
    second.add(_frame());
    await Future<void>.delayed(Duration.zero);

    expect(count, 2);
  });

  test('a transport that fails stops the stream and says why', () async {
    final frames = StreamController<EncodedVideoFrame>();
    addTearDown(frames.close);
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      sink: (frame) => throw StateError('socket closed'),
    )..attach(frames.stream);

    frames.add(_frame());
    await Future<void>.delayed(Duration.zero);

    expect(transport.error, isNotNull);
    expect(transport.sentPackets, 0);

    // And the detachment is real: a later frame is not attempted.
    frames.add(_frame());
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentPackets, 0);
  });

  test('an error on the frame stream is reported, not thrown', () async {
    final frames = StreamController<EncodedVideoFrame>();
    addTearDown(frames.close);
    final transport = DiscordVideoStreamTransport(ssrc: 1, sink: (frame) => 0)
      ..attach(frames.stream);

    frames.addError(StateError('encoder died'));
    await Future<void>.delayed(Duration.zero);

    expect(transport.error, isNotNull);
  });

  test('the sequence continues where a caller resumed it', () {
    final sent = <DiscordRtpFrame>[];
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      initialSequence: 0xfffe,
      sink: (frame) {
        sent.add(frame);
        return 0;
      },
    );

    transport.send(_frame());
    transport.send(_frame());

    expect(sent.map((frame) => frame.header.sequence), [0xfffe, 0xffff, 0, 1]);
  });

  test('a NACKed packet is resent on the rtx ssrc with its sequence ahead', () {
    final sent = <DiscordRtpFrame>[];
    final transport = DiscordVideoStreamTransport(
      ssrc: 0x1000,
      rtxSsrc: 0x2000,
      sink: (frame) {
        sent.add(frame);
        return 0;
      },
    );

    // Two packets of one picture go out, sequences 0 and 1.
    transport.send(_frame(sliceLength: 8, isKeyframe: true));
    sent.clear();

    final resent = transport.retransmit([1]);

    expect(resent, 1);
    expect(transport.retransmittedPackets, 1);
    expect(sent, hasLength(1));
    final rtx = sent.single;
    // On the retransmission SSRC and payload type, in its own sequence.
    expect(rtx.header.ssrc, 0x2000);
    expect(rtx.header.payloadType, DiscordRtpHeader.discordVideoRtxPayloadType);
    expect(rtx.header.sequence, 0);
    // The original sequence (1) leads the payload so the receiver can place it.
    expect(rtx.payload.first, 0);
    expect(rtx.payload[1], 1);
  });

  test('a sequence no longer held is skipped', () {
    var count = 0;
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      sink: (frame) {
        count++;
        return 0;
      },
    );

    transport.send(_frame());
    count = 0;

    // Sequence 999 was never sent: nothing goes out for it.
    expect(transport.retransmit([999]), 0);
    expect(count, 0);
  });

  test('group encryption covers the whole picture, once, before packets', () {
    final encrypted = <Uint8List>[];
    final sent = <DiscordRtpFrame>[];
    // Group ciphertext that still parses as a stream: DAVE encrypts ranges,
    // so the NAL structure a receiver packetises on survives it.
    final ciphertext = Uint8List.fromList([0, 0, 0, 1, 0x41, 0xee, 0xff]);
    final transport = DiscordVideoStreamTransport(
      ssrc: 1,
      sink: (frame) {
        sent.add(frame);
        return 0;
      },
      groupEncryptor: (frame) {
        encrypted.add(frame);
        return ciphertext;
      },
    );

    final frame = _frame(sliceLength: 8);
    transport.send(frame);

    // One call per picture, on the whole access unit: receivers reassemble a
    // frame and decrypt once, so per-packet ciphertext is undecryptable.
    expect(encrypted, hasLength(1));
    expect(encrypted.single.length, frame.bytes.length);
    // And what went on the wire is the encrypted bytes, not the clear ones.
    expect(sent, hasLength(1));
    expect(sent.single.payload, [0x41, 0xee, 0xff]);
  });
}

/// A clock the test moves by hand, in step with [FakeAsync.elapse].
final class _Clock {
  DateTime now = DateTime(2026, 8, 24);
  void elapse(FakeAsync async, Duration by) {
    now = now.add(by);
    async.elapse(by);
  }
}

void _pacingTests() {
  // 8 kbit/s paces at 2.5x = 2500 bytes/s: one 100-byte packet every 40 ms.
  const bitsPerSecond = 8000;

  test('a paced frame leaves one packet at a time, not in a burst', () {
    fakeAsync((async) {
      final clock = _Clock();
      final sent = <DiscordRtpFrame>[];
      final transport = DiscordVideoStreamTransport(
        ssrc: 1,
        sink: (frame) {
          sent.add(frame);
          return 0;
        },
        maxPayloadSize: 100,
        pacingBitsPerSecond: bitsPerSecond,
        now: () => clock.now,
      );

      final queued = transport.send(_frame(sliceLength: 430));

      expect(queued, 6);
      // The first packet goes out at once; the rest wait for budget.
      expect(sent, hasLength(1));
      clock.elapse(async, const Duration(milliseconds: 100));
      expect(sent.length, inExclusiveRange(1, 6));
      clock.elapse(async, const Duration(milliseconds: 400));
      expect(sent, hasLength(6));
      expect(sent.map((frame) => frame.header.sequence), [0, 1, 2, 3, 4, 5]);
      expect(transport.sentPackets, 6);
      expect(transport.queuedPackets, 0);
    });
  });

  test('budget does not pile up while the queue is empty', () {
    fakeAsync((async) {
      final clock = _Clock();
      var count = 0;
      final transport = DiscordVideoStreamTransport(
        ssrc: 1,
        sink: (frame) {
          count++;
          return 0;
        },
        maxPayloadSize: 100,
        pacingBitsPerSecond: bitsPerSecond,
        now: () => clock.now,
      );

      // A long silence, then a frame: still one packet at once, no burst.
      clock.elapse(async, const Duration(seconds: 5));
      transport.send(_frame(sliceLength: 430));
      expect(count, 1);
    });
  });

  test('a retransmission goes ahead of the queue', () {
    fakeAsync((async) {
      final clock = _Clock();
      final sent = <DiscordRtpFrame>[];
      final transport = DiscordVideoStreamTransport(
        ssrc: 1,
        sink: (frame) {
          sent.add(frame);
          return 0;
        },
        maxPayloadSize: 100,
        pacingBitsPerSecond: bitsPerSecond,
        now: () => clock.now,
      );
      transport.send(_frame(sliceLength: 430));
      expect(sent, hasLength(1));

      expect(transport.retransmit([0]), 1);

      expect(sent, hasLength(2));
      expect(sent.last.header.ssrc, 2);
    });
  });

  test('stopping drops what was still queued', () {
    fakeAsync((async) {
      final clock = _Clock();
      var count = 0;
      final transport = DiscordVideoStreamTransport(
        ssrc: 1,
        sink: (frame) {
          count++;
          return 0;
        },
        maxPayloadSize: 100,
        pacingBitsPerSecond: bitsPerSecond,
        now: () => clock.now,
      );
      transport.send(_frame(sliceLength: 430));
      transport.stop();
      clock.elapse(async, const Duration(seconds: 1));

      expect(count, 1);
      expect(transport.queuedPackets, 0);
    });
  });
}
