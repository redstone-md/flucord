import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flucord/src/application/watched_session_pipeline.dart';
import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_media_transport.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_audio.dart';

/// A parameter set and an IDR slice: the picture that restarts a decoder.
Uint8List _idrUnit({int sliceLength = 8}) => Uint8List.fromList([
  0,
  0,
  0,
  1,
  0x67,
  0x42,
  0x00,
  0,
  0,
  0,
  1,
  0x65,
  ...List.filled(sliceLength, 0xaa),
]);

final Uint8List _idr = _idrUnit();

/// An IDR whose slice spans several packets.
final Uint8List _bigIdr = _idrUnit(sliceLength: 1400);

/// A picture that references an earlier one.
final Uint8List _pFrame = Uint8List.fromList([
  0,
  0,
  0,
  1,
  0x41,
  ...List.filled(8, 0xbb),
]);

/// One small picture, as a decoder hands it out.
final DecodedVideoFrame _picture = DecodedVideoFrame(
  pixels: Uint8List.fromList([1, 2, 3, 4]),
  width: 1,
  height: 1,
  timestamp: Duration.zero,
);

/// The packets [unit] becomes on the wire.
List<IncomingVideoPacket> _packets(Uint8List unit, {int rtpTimestamp = 0}) => [
  for (final payload in DiscordH264Packetizer.packetize(unit))
    IncomingVideoPacket(
      payload: payload.bytes,
      marker: payload.isLast,
      rtpTimestamp: rtpTimestamp,
    ),
];

void _feed(WatchedSessionPipeline pipeline, Uint8List unit, {int rtp = 0}) {
  for (final packet in _packets(unit, rtpTimestamp: rtp)) {
    pipeline.accept(packet);
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'a picture still arriving submits nothing; the closing packet submits one',
    () async {
      final decoder = _FakeDecoder();
      final pipeline = WatchedSessionPipeline(decoderFactory: () => decoder);
      addTearDown(pipeline.close);
      await pipeline.setDecoding(true);

      final packets = _packets(_idr);
      expect(packets.length, 2);
      pipeline.accept(packets.first);
      expect(decoder.submitted, isEmpty);
      expect(pipeline.stats.receivedPackets, 1);
      expect(pipeline.stats.pictures, 0);

      pipeline.accept(packets.last);
      expect(decoder.submitted, hasLength(1));
      expect(pipeline.stats.receivedPackets, 2);
      expect(pipeline.stats.pictures, 1);
    },
  );

  test('the first picture is news once, not every picture', () async {
    final decoder = _FakeDecoder();
    var told = 0;
    final pipeline = WatchedSessionPipeline(
      decoderFactory: () => decoder,
      onFirstPicture: () => told++,
    );
    addTearDown(pipeline.close);
    await pipeline.setDecoding(true);

    for (var picture = 0; picture < 100; picture++) {
      _feed(pipeline, _idr);
    }

    expect(decoder.submitted, hasLength(100));
    expect(told, 1);
  });

  test(
    'a picture that will not decrypt is dropped and asks nothing by itself',
    () async {
      final decoder = _FakeDecoder();
      var asks = 0;
      var reject = true;
      final pipeline = WatchedSessionPipeline(
        decoderFactory: () => decoder,
        groupDecryptor: (picture) {
          if (reject) throw StateError('no key yet');
          return picture;
        },
        requestKeyframe: () => asks++,
      );
      addTearDown(pipeline.close);
      await pipeline.setDecoding(true);

      // A key that has not reached this client yet is ordinary at the start of
      // a stream (ADR-0005), so nothing is asked for.
      _feed(pipeline, _idr);
      expect(decoder.submitted, isEmpty);
      expect(asks, 0);

      // The picture that failed carried references. The next one opens, and is
      // held back rather than drawn from references the decoder never saw.
      reject = false;
      _feed(pipeline, _pFrame);
      expect(decoder.submitted, isEmpty);
      expect(asks, 1);

      _feed(pipeline, _idr);
      expect(decoder.submitted, hasLength(1));
    },
  );

  test('a pacer overflow with no keyframe queued breaks the references', () {
    fakeAsync((async) {
      final decoder = _FakeDecoder();
      var asks = 0;
      final pipeline = WatchedSessionPipeline(
        decoderFactory: () => decoder,
        requestKeyframe: () => asks++,
        now: () => async.elapsed,
      );
      unawaited(pipeline.setDecoding(true));
      async.flushMicrotasks();

      // The first picture anchors the schedule and decodes at once. Every
      // picture after it is due a few milliseconds later, so the queue fills
      // with pictures whose slots have not come.
      _feed(pipeline, _idr, rtp: 90000);
      expect(decoder.submitted, hasLength(1));
      for (var index = 1; index <= 48; index++) {
        _feed(pipeline, _pFrame, rtp: 90000 + 300 * index);
      }
      expect(decoder.submitted, hasLength(1));
      expect(asks, 0);

      // One more and the queue is dropped whole: nothing in it was a
      // keyframe, so what follows is drawn from references that are gone.
      _feed(pipeline, _pFrame, rtp: 90000 + 300 * 49);
      expect(pipeline.stats.pacerOverflows, 1);
      expect(asks, 1);

      // Held back, and the ask is not repeated inside a second.
      _feed(pipeline, _pFrame, rtp: 90000 + 300 * 50);
      expect(decoder.submitted, hasLength(2));
      expect(asks, 1);

      async.elapse(const Duration(seconds: 1));
      _feed(pipeline, _pFrame, rtp: 90000 + 300 * 51);
      expect(asks, 2);

      // A keyframe mends the references and is decoded.
      _feed(pipeline, _idr, rtp: 90000 + 300 * 52);
      expect(decoder.submitted, hasLength(3));
      unawaited(pipeline.close());
      async.flushMicrotasks();
    });
  });

  test('a dropped access unit breaks the references the same way', () async {
    final decoder = _FakeDecoder();
    var asks = 0;
    final pipeline = WatchedSessionPipeline(
      decoderFactory: () => decoder,
      requestKeyframe: () => asks++,
    );
    addTearDown(pipeline.close);
    await pipeline.setDecoding(true);
    _feed(pipeline, _idr);
    expect(decoder.submitted, hasLength(1));

    decoder.drop(1);
    await _flush();
    expect(asks, 1);

    _feed(pipeline, _pFrame);
    expect(decoder.submitted, hasLength(1));

    _feed(pipeline, _idr);
    expect(decoder.submitted, hasLength(2));
  });

  test('several broken-reference sources in one second ask once', () async {
    final decoder = _FakeDecoder();
    var asks = 0;
    var clock = Duration.zero;
    var reject = false;
    final pipeline = WatchedSessionPipeline(
      decoderFactory: () => decoder,
      groupDecryptor: (picture) {
        if (reject) throw StateError('no key');
        return picture;
      },
      requestKeyframe: () => asks++,
      now: () => clock,
    );
    addTearDown(pipeline.close);
    await pipeline.setDecoding(true);
    _feed(pipeline, _idr);

    // A picture that will not decrypt, a dropped access unit, and a picture
    // held back: three reasons, one ask.
    reject = true;
    _feed(pipeline, _pFrame);
    reject = false;
    decoder.drop(1);
    await _flush();
    _feed(pipeline, _pFrame);
    expect(asks, 1);

    // The next second may ask again, and a keyframe ends it.
    clock = const Duration(seconds: 1);
    _feed(pipeline, _pFrame);
    expect(asks, 2);
    _feed(pipeline, _idr);
    clock = const Duration(seconds: 3);
    _feed(pipeline, _pFrame);
    expect(asks, 2);
    expect(decoder.submitted, hasLength(3));
  });

  test('decoding off keeps counting packets and submits nothing', () async {
    final decoder = _FakeDecoder();
    final pipeline = WatchedSessionPipeline(decoderFactory: () => decoder);
    addTearDown(pipeline.close);
    await pipeline.setDecoding(true);
    _feed(pipeline, _idr);

    await pipeline.setDecoding(false);
    expect(decoder.stopped, 1);

    _feed(pipeline, _idr);
    expect(pipeline.stats.receivedPackets, 4);
    expect(pipeline.stats.pictures, 1);
    expect(decoder.submitted, hasLength(1));

    // Off twice lets nothing go twice.
    await pipeline.setDecoding(false);
    expect(decoder.stopped, 1);
  });

  test('decoding on again submits only from the next keyframe', () async {
    final made = <_FakeDecoder>[];
    final pipeline = WatchedSessionPipeline(
      decoderFactory: () {
        final decoder = _FakeDecoder();
        made.add(decoder);
        return decoder;
      },
    );
    addTearDown(pipeline.close);
    await pipeline.setDecoding(true);
    // Half a picture, as a window going away mid-picture leaves it: the
    // parameter set and the first fragment of the slice.
    for (final packet in _packets(_bigIdr).take(2)) {
      pipeline.accept(packet);
    }

    await pipeline.setDecoding(false);
    await pipeline.setDecoding(true);
    expect(made, hasLength(2));

    // The rest of that picture is not the start of one, and a picture built
    // on references from before the window went away is not drawn either.
    pipeline.accept(_packets(_bigIdr).last);
    _feed(pipeline, _pFrame);
    expect(made.last.submitted, isEmpty);

    _feed(pipeline, _bigIdr);
    expect(made.last.submitted, hasLength(1));
    expect(made.first.submitted, isEmpty);
  });

  test('the frames it exposes follow the decoder across suspension', () async {
    final made = <_FakeDecoder>[];
    final pipeline = WatchedSessionPipeline(
      decoderFactory: () {
        final decoder = _FakeDecoder();
        made.add(decoder);
        return decoder;
      },
    );
    addTearDown(pipeline.close);
    final drawn = <DecodedVideoFrame>[];
    final frames = pipeline.frames.listen(drawn.add);
    addTearDown(frames.cancel);

    await pipeline.setDecoding(true);
    made.single.emit(_picture);
    await _flush();
    expect(drawn, hasLength(1));

    await pipeline.setDecoding(false);
    await pipeline.setDecoding(true);
    made.first.emit(_picture);
    made.last.emit(_picture);
    await _flush();

    // One subscription for the room, whichever decoder is behind it, and
    // nothing from the one that was let go.
    expect(drawn, hasLength(2));
    expect(pipeline.stats.decodedFrames, 2);
  });

  test('two "on" calls leave one decoder', () async {
    final gate = Completer<void>();
    final made = <_FakeDecoder>[];
    final pipeline = WatchedSessionPipeline(
      decoderFactory: () {
        final decoder = _FakeDecoder(startGate: gate);
        made.add(decoder);
        return decoder;
      },
    );
    addTearDown(pipeline.close);

    final first = pipeline.setDecoding(true);
    final second = pipeline.setDecoding(true);
    gate.complete();
    await Future.wait([first, second]);

    expect(made, hasLength(1));
    expect(made.single.started, 1);
    expect(made.single.stopped, 0);
  });

  test('turned off while a decoder opens hands it back', () async {
    final gate = Completer<void>();
    final decoder = _FakeDecoder(startGate: gate);
    final pipeline = WatchedSessionPipeline(decoderFactory: () => decoder);
    addTearDown(pipeline.close);

    final opening = pipeline.setDecoding(true);
    await pipeline.setDecoding(false);
    gate.complete();
    await opening;

    expect(decoder.stopped, 1);
    _feed(pipeline, _idr);
    expect(decoder.submitted, isEmpty);
  });

  test('closing while a decoder opens hands it back', () async {
    final gate = Completer<void>();
    final decoder = _FakeDecoder(startGate: gate);
    final pipeline = WatchedSessionPipeline(decoderFactory: () => decoder);

    final opening = pipeline.setDecoding(true);
    await pipeline.close();
    gate.complete();
    await opening;

    expect(decoder.stopped, 1);
    // Nothing reopens after close.
    await pipeline.setDecoding(true);
    expect(decoder.started, 1);
  });

  test(
    'a decoder that will not open is reported and leaves nothing behind',
    () async {
      final decoder = _FakeDecoder(failStart: true);
      final pipeline = WatchedSessionPipeline(decoderFactory: () => decoder);
      addTearDown(pipeline.close);

      await expectLater(pipeline.setDecoding(true), throwsStateError);

        _feed(pipeline, _idr);
      expect(decoder.submitted, isEmpty);
    },
  );

  test('with pacing off a picture is submitted the moment it closes', () {
    fakeAsync((async) {
      final decoder = _FakeDecoder();
      final pipeline = WatchedSessionPipeline(
        decoderFactory: () => decoder,
        paced: false,
        now: () => async.elapsed,
      );
      unawaited(pipeline.setDecoding(true));
      async.flushMicrotasks();

      // Timestamps a pacer would hold for their slots.
      _feed(pipeline, _idr, rtp: 90000);
      _feed(pipeline, _pFrame, rtp: 93000);
      _feed(pipeline, _pFrame, rtp: 96000);
      expect(decoder.submitted, hasLength(3));
      unawaited(pipeline.close());
      async.flushMicrotasks();
    });
  });

  group('screen-share audio', () {
    test(
      'audio attached at construction plays, and ends with the close',
      () async {
        final codecs = FakeVoiceOpusDecoderFactory();
        final opus = StreamController<VoiceRemoteOpusFrame>.broadcast();
        addTearDown(opus.close);
        final pipeline = WatchedSessionPipeline(
          decoderFactory: _FakeDecoder.new,
          audio: (
            frames: opus.stream,
            decoderFactory: codecs,
            sourceId: 'stream:call:dm-1:them:1',
          ),
        );
        final heard = <VoiceRemotePcmFrame>[];
        final ended = <String>[];
        final pcm = pipeline.pcm.listen(heard.add);
        final ending = pipeline.audioEnded.listen(ended.add);
        addTearDown(pcm.cancel);
        addTearDown(ending.cancel);
        await _flush();

        // Sound plays whether or not pictures are being decoded (ADR-0003).
        opus.add(
          VoiceRemoteOpusFrame(userId: 'them', opus: Uint8List.fromList([7])),
        );
        await _flush();
        expect(codecs.created, 1);
        expect(heard.single.userId, 'them');
        expect(heard.single.sourceId, 'stream:call:dm-1:them:1');
        expect(heard.single.samples, [7]);

        await pipeline.close();
        expect(codecs.disposed, 1);
        expect(ended, ['stream:call:dm-1:them:1']);

        opus.add(
          VoiceRemoteOpusFrame(userId: 'them', opus: Uint8List.fromList([8])),
        );
        await _flush();
        expect(heard, hasLength(1));
      },
    );

    test('a session without audio ends no source', () async {
      final pipeline = WatchedSessionPipeline(decoderFactory: _FakeDecoder.new);
      final ended = <String>[];
      final ending = pipeline.audioEnded.listen(ended.add);
      addTearDown(ending.cancel);

      await pipeline.close();
      expect(ended, isEmpty);
    });

    test('the stream media receive path feeds the decoder', () async {
      final incoming = StreamController<DiscordRtpFrame>.broadcast();
      addTearDown(incoming.close);
      final transport = DiscordVoiceMediaTransport(
        incomingFrames: incoming.stream,
        encryptDave: (frame) => frame,
        decryptDave: (_, frame) => Uint8List.fromList(frame.sublist(1)),
        sendFrame: (_) => 1,
        sendSpeaking: (_) {},
        userForSsrc: (ssrc) => ssrc == 7 ? 'them' : null,
      )..configure(ssrc: 42, daveEnabled: true);
      final pipeline = WatchedSessionPipeline(
        decoderFactory: _FakeDecoder.new,
        audio: (
          frames: transport.remoteAudio,
          decoderFactory: FakeVoiceOpusDecoderFactory(),
          sourceId: 'stream:call:dm-1:them:1',
        ),
      );
      addTearDown(pipeline.close);
      final heard = <VoiceRemotePcmFrame>[];
      final pcm = pipeline.pcm.listen(heard.add);
      addTearDown(pcm.cancel);
      await _flush();

      incoming.add(
        DiscordRtpFrame(
          header: DiscordRtpHeader(sequence: 1, timestamp: 1, ssrc: 7),
          payload: const [0xd0, 7],
        ),
      );
      await _flush();

      expect(heard.single.userId, 'them');
      expect(heard.single.samples, [7]);
    });
  });
}

final class _FakeDecoder implements VideoDecoderService {
  _FakeDecoder({this.failStart = false, this.startGate});

  final bool failStart;

  /// Held shut so a test can act while the decoder is still opening.
  final Completer<void>? startGate;
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  final StreamController<int> _drops = StreamController.broadcast();
  final List<Uint8List> submitted = [];
  int started = 0;
  int stopped = 0;

  void emit(DecodedVideoFrame frame) => _frames.add(frame);

  void drop(int total) => _drops.add(total);

  @override
  bool get isSupported => true;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Stream<int> get droppedAccessUnits => _drops.stream;

  @override
  Future<void> start() async {
    if (failStart) throw StateError('no decoder');
    await startGate?.future;
    started++;
  }

  @override
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp}) async =>
      submitted.add(accessUnit);

  @override
  Future<void> stop() async => stopped++;
}
