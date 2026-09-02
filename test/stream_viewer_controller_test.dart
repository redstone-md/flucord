import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/application/watched_session_pipeline.dart';
import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_audio.dart';

const _key = GoLiveStreamKey.call(channelId: 'dm-1', userId: 'them');
const _other = GoLiveStreamKey.guild(guildId: 'g', channelId: 'c', userId: 'u');

/// One small picture, as a decoder hands it to whatever draws it.
final DecodedVideoFrame _picture = DecodedVideoFrame(
  pixels: Uint8List.fromList([1, 2, 3, 4]),
  width: 1,
  height: 1,
  timestamp: Duration.zero,
);

/// The packets one small access unit becomes, as a stream connection would
/// deliver them.
List<IncomingVideoPacket> _packetsFor({int sliceLength = 8}) => [
  for (final payload in DiscordH264Packetizer.packetize(
    Uint8List.fromList([
      0,
      0,
      0,
      1,
      0x67,
      0x42,
      0,
      0,
      1,
      0x65,
      ...List.filled(sliceLength, 0xaa),
    ]),
  ))
    IncomingVideoPacket(payload: payload.bytes, marker: payload.isLast),
];

/// Creates an Opus frame.
VoiceRemoteOpusFrame _opusFrame(String userId, List<int> opus) =>
    VoiceRemoteOpusFrame(userId: userId, opus: Uint8List.fromList(opus));

/// Creates an audio stream that can outlive a watched session.
StreamController<VoiceRemoteOpusFrame> _audioConnection() {
  final controller = StreamController<VoiceRemoteOpusFrame>.broadcast();
  addTearDown(controller.close);
  return controller;
}

void main() {
  test('a build that cannot decode watches nothing', () async {
    final repository = _FakeRepository();
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => _FakeDecoder(supported: false),
    );
    addTearDown(controller.dispose);

    expect(
      await controller.watch(_key, packets: const Stream.empty()),
      isFalse,
    );
    expect(controller.isSupported, isFalse);
    expect(repository.watched, isEmpty);
  });

  test('a transport with no stream plane watches nothing', () async {
    final controller = StreamViewerController(
      repositoryProvider: () => null,
      decoderFactory: () => _FakeDecoder(),
    );
    addTearDown(controller.dispose);

    expect(
      await controller.watch(_key, packets: const Stream.empty()),
      isFalse,
    );
  });

  test('asks Discord first, then decodes what arrives', () async {
    final repository = _FakeRepository();
    final decoder = _FakeDecoder();
    final packets = StreamController<IncomingVideoPacket>();
    addTearDown(packets.close);
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => decoder,
    );
    addTearDown(controller.dispose);

    expect(await controller.watch(_key, packets: packets.stream), isTrue);

    // Discord does not send the picture to a client that never asked, so the
    // ask comes before the decoder is opened.
    expect(repository.watched, [_key]);
    expect(decoder.started, 1);
    expect(controller.watching, _key);

    for (final packet in _packetsFor()) {
      packets.add(packet);
    }
    await Future<void>.delayed(Duration.zero);

    expect(controller.receivedPackets, 2);
    // Two packets, one picture: the count that matters is the second.
    expect(controller.decodedUnits, 1);
    expect(decoder.submitted.length, 1);
    expect(
      DiscordH264Packetizer.splitAnnexB(decoder.submitted.single).length,
      2,
    );
  });

  test('stopping releases the decoder and forgets the counts', () async {
    final repository = _FakeRepository();
    final decoder = _FakeDecoder();
    final packets = StreamController<IncomingVideoPacket>();
    addTearDown(packets.close);
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => decoder,
    );
    addTearDown(controller.dispose);
    await controller.watch(_key, packets: packets.stream);
    for (final packet in _packetsFor()) {
      packets.add(packet);
    }
    await Future<void>.delayed(Duration.zero);

    await controller.stop();

    expect(decoder.stopped, 1);
    expect(controller.watching, isNull);
    expect(controller.receivedPackets, 0);
    expect(controller.decodedUnits, 0);

    // Packets arriving after the stop go nowhere.
    packets.add(_packetsFor().first);
    await Future<void>.delayed(Duration.zero);
    expect(controller.receivedPackets, 0);

    // Stopping twice is what a closing surface does.
    await controller.stop();
    expect(decoder.stopped, 1);
  });

  test('stopping a watch tells Discord, so the next ask is answered', () async {
    final repository = _FakeRepository();
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => _FakeDecoder(),
    );
    addTearDown(controller.dispose);
    await controller.watch(_key, packets: const Stream.empty());

    await controller.stop(_key);

    // Discord keeps this client on the viewer list until it is told
    // otherwise, and answers no second STREAM_WATCH for a stream it thinks
    // is already being watched.
    expect(repository.stoppedWatching, [_key]);
    expect(repository.ended, isEmpty, reason: 'the stream is not ours to end');

    expect(await controller.requestWatch(_key), isTrue);
    expect(repository.watched, [_key, _key]);
  });

  test('an ask withdrawn before it arrived is told to Discord too', () async {
    final repository = _FakeRepository();
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => _FakeDecoder(),
    );
    addTearDown(controller.dispose);
    await controller.requestWatch(_key);

    await controller.stop(_key);

    expect(repository.stoppedWatching, [_key]);
  });

  test(
    'asking again while the previous watch closes is not withdrawn',
    () async {
      final repository = _FakeRepository();
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () => _FakeDecoder(),
      );
      addTearDown(controller.dispose);
      await controller.requestWatch(_key);

      // Stop and re-ask in the same turn, the way a double press lands.
      final stopping = controller.stop(_key);
      final asking = controller.requestWatch(_key);
      await stopping;
      expect(await asking, isTrue);

      expect(
        await controller.attach(_key, packets: const Stream.empty()),
        isTrue,
        reason: 'the withdrawal was against the first ask, not this one',
      );
    },
  );

  test('the connection is told to drop before the decoder is let go', () {
    final stopped = <GoLiveStreamKey>[];
    final controller = StreamViewerController(
      repositoryProvider: () => _FakeRepository(),
      decoderFactory: () => _FakeDecoder(),
      onWatchStopped: stopped.add,
    );
    addTearDown(controller.dispose);
    unawaited(controller.watch(_key, packets: const Stream.empty()));

    unawaited(controller.stop(_key));

    // Synchronous with the decision: a connection Discord reopens for a new
    // ask meanwhile must not be the one this stop takes down.
    expect(stopped, [_key]);
  });

  test(
    'the stream asked for last takes the stage, the other stays open',
    () async {
      final repository = _FakeRepository();
      final decoder = _FakeDecoder();
      final first = StreamController<IncomingVideoPacket>();
      final second = StreamController<IncomingVideoPacket>();
      addTearDown(first.close);
      addTearDown(second.close);
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () => decoder,
      );
      addTearDown(controller.dispose);

      await controller.watch(_key, packets: first.stream);
      const other = GoLiveStreamKey.guild(
        guildId: 'g',
        channelId: 'c',
        userId: 'u',
      );
      await controller.watch(other, packets: second.stream);

      first.add(_packetsFor().first);
      await Future<void>.delayed(Duration.zero);

      expect(controller.watching, other);
      // Replaced on the stage, not closed: it is still read, its packets just
      // are not the ones the stage is counting.
      expect(controller.isWatching(_key), isTrue);
      expect(controller.receivedPacketsFor(_key), 1);
      expect(controller.receivedPacketsFor(other), 0);
      expect(controller.receivedPackets, 0);
    },
  );

  test('a refused watch is reported and starts no decoder', () async {
    final repository = _FakeRepository(failWatch: true);
    final decoder = _FakeDecoder();
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => decoder,
    );
    addTearDown(controller.dispose);

    expect(
      await controller.watch(_key, packets: const Stream.empty()),
      isFalse,
    );

    expect(controller.error, isNotNull);
    expect(decoder.started, 0);
    expect(controller.watching, isNull);
  });

  test('a decoder that will not open is reported', () async {
    final repository = _FakeRepository();
    final decoder = _FakeDecoder(failStart: true);
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => decoder,
    );
    addTearDown(controller.dispose);

    expect(
      await controller.watch(_key, packets: const Stream.empty()),
      isFalse,
    );

    expect(controller.error, isNotNull);
  });

  test('an error on the packet stream is reported, not thrown', () async {
    final repository = _FakeRepository();
    final packets = StreamController<IncomingVideoPacket>();
    addTearDown(packets.close);
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => _FakeDecoder(),
    );
    addTearDown(controller.dispose);
    await controller.watch(_key, packets: packets.stream);

    packets.addError(StateError('connection lost'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.error, isNotNull);
  });

  test('the frames it exposes are the decoder\'s own', () async {
    final repository = _FakeRepository();
    final decoder = _FakeDecoder();
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => decoder,
    );
    addTearDown(controller.dispose);
    addTearDown(decoder.close);
    await controller.watch(_key, packets: const Stream.empty());

    final seen = <DecodedVideoFrame>[];
    final subscription = controller.framesFor(_key).listen(seen.add);
    addTearDown(subscription.cancel);
    decoder.emit(
      DecodedVideoFrame(
        pixels: Uint8List(16),
        width: 2,
        height: 2,
        timestamp: Duration.zero,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(seen.single.width, 2);
  });

  group('asking first, decoding later', () {
    test('the ask goes out before any endpoint exists', () async {
      final repository = _FakeRepository();
      final decoder = _FakeDecoder();
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () => decoder,
      );
      addTearDown(controller.dispose);

      expect(await controller.requestWatch(_key), isTrue);

      // Discord answers with an endpoint seconds later, and only the
      // connection that answer opens carries pictures. Nothing is decoded yet.
      expect(repository.watched, [_key]);
      expect(controller.requested, _key);
      expect(controller.watching, isNull);
      expect(decoder.started, 0);
    });

    test('an unsolicited endpoint stays silent', () async {
      final audioCodecs = FakeVoiceOpusDecoderFactory();
      final controller = StreamViewerController(
        repositoryProvider: () => _FakeRepository(),
        decoderFactory: () => _FakeDecoder(),
        audioDecoderFactory: audioCodecs,
      );
      addTearDown(controller.dispose);
      final packets = StreamController<IncomingVideoPacket>.broadcast();
      addTearDown(packets.close);
      final audio = _audioConnection();
      final heard = <VoiceRemotePcmFrame>[];
      final playback = controller.audio.listen(heard.add);
      addTearDown(playback.cancel);

      expect(
        await controller.attach(
          _key,
          packets: packets.stream,
          audio: audio.stream,
        ),
        isFalse,
      );
      audio.add(_opusFrame('them', [7]));
      await Future<void>.delayed(Duration.zero);

      expect(controller.isOpen(_key), isFalse);
      expect(controller.isWatching(_key), isFalse);
      expect(audioCodecs.created, 0);
      expect(heard, isEmpty);
    });

    test('attaching decodes without asking a second time', () async {
      final repository = _FakeRepository();
      final decoder = _FakeDecoder();
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () => decoder,
      );
      addTearDown(controller.dispose);
      final packets = StreamController<IncomingVideoPacket>();
      addTearDown(packets.close);

      await controller.requestWatch(_key);
      expect(await controller.attach(_key, packets: packets.stream), isTrue);

      // A second ask would open a second connection for one stream.
      expect(repository.watched, [_key]);
      expect(controller.watching, _key);
      expect(controller.requested, isNull);

      for (final packet in _packetsFor()) {
        packets.add(packet);
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.decodedUnits, greaterThan(0));
    });

    test('an ask Discord refuses stops claiming to be waiting', () async {
      final repository = _FakeRepository(failWatch: true);
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () => _FakeDecoder(),
      );
      addTearDown(controller.dispose);

      expect(await controller.requestWatch(_key), isFalse);

      expect(controller.requested, isNull);
      expect(controller.error, isNotNull);
    });

    test('a build that cannot decode neither asks nor attaches', () async {
      final repository = _FakeRepository();
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () => _FakeDecoder(supported: false),
      );
      addTearDown(controller.dispose);

      expect(await controller.requestWatch(_key), isFalse);
      expect(
        await controller.attach(_key, packets: const Stream.empty()),
        isFalse,
      );
      expect(repository.watched, isEmpty);
    });

    test('stopping forgets a stream that was only asked for', () async {
      final repository = _FakeRepository();
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () => _FakeDecoder(),
      );
      addTearDown(controller.dispose);

      await controller.requestWatch(_key);
      await controller.stop();

      expect(controller.requested, isNull);
    });

    test(
      'a withdrawn ask is not attached when Discord answers anyway',
      () async {
        final decoder = _FakeDecoder();
        final controller = StreamViewerController(
          repositoryProvider: () => _FakeRepository(),
          decoderFactory: () => decoder,
        );
        addTearDown(controller.dispose);

        await controller.requestWatch(_key);
        await controller.stop();

        expect(
          await controller.attach(_key, packets: const Stream.empty()),
          isFalse,
        );
        expect(controller.watching, isNull);
        expect(decoder.started, 0);
      },
    );

    test('asking again overrides a withdrawal', () async {
      final decoder = _FakeDecoder();
      final controller = StreamViewerController(
        repositoryProvider: () => _FakeRepository(),
        decoderFactory: () => decoder,
      );
      addTearDown(controller.dispose);

      await controller.requestWatch(_key);
      await controller.stop();
      await controller.requestWatch(_key);

      expect(
        await controller.attach(_key, packets: const Stream.empty()),
        isTrue,
      );
      expect(controller.watching, _key);
    });

    test(
      'a decoder that will not start reports rather than half-attaches',
      () async {
        final controller = StreamViewerController(
          repositoryProvider: () => _FakeRepository(),
          decoderFactory: () => _FakeDecoder(failStart: true),
        );
        addTearDown(controller.dispose);

        await controller.requestWatch(_key);
        expect(
          await controller.attach(_key, packets: const Stream.empty()),
          isFalse,
        );
        expect(controller.watching, isNull);
        expect(controller.error, isNotNull);
      },
    );
  });

  group('several at once', () {
    test('each session decodes through a decoder of its own', () async {
      final repository = _FakeRepository();
      final first = StreamController<IncomingVideoPacket>();
      final second = StreamController<IncomingVideoPacket>();
      addTearDown(first.close);
      addTearDown(second.close);
      final made = <_FakeDecoder>[];
      final controller = _viewer(repository, made: made);
      addTearDown(controller.dispose);

      await controller.watch(_key, packets: first.stream);
      await controller.watch(_other, packets: second.stream);

      // Two streams, two decoders: a decoder shared between them has
      // nowhere to put the second one's pictures.
      expect(made, hasLength(2));
      expect(controller.isWatching(_key), isTrue);
      expect(controller.isWatching(_other), isTrue);
    });

    test('one stream\'s packets do not land in another\'s picture', () async {
      final repository = _FakeRepository();
      final first = StreamController<IncomingVideoPacket>();
      final second = StreamController<IncomingVideoPacket>();
      addTearDown(first.close);
      addTearDown(second.close);
      final controller = _viewer(repository);
      addTearDown(controller.dispose);

      await controller.watch(_key, packets: first.stream);
      await controller.watch(_other, packets: second.stream);

      for (final packet in _packetsFor()) {
        first.add(packet);
      }
      second.add(_packetsFor().first);
      await Future<void>.delayed(Duration.zero);

      // Two packets are a whole access unit and one is half of one. A
      // depacketiser shared between the two would splice the halves into one
      // picture and count it against whichever stream came second.
      expect(controller.receivedPacketsFor(_key), 2);
      expect(controller.decodedUnitsFor(_key), 1);
      expect(controller.receivedPacketsFor(_other), 1);
      expect(controller.decodedUnitsFor(_other), 0);
    });

    test('stopping one leaves the others running', () async {
      final repository = _FakeRepository();
      final first = StreamController<IncomingVideoPacket>();
      final second = StreamController<IncomingVideoPacket>();
      addTearDown(first.close);
      addTearDown(second.close);
      final made = <_FakeDecoder>[];
      final controller = _viewer(repository, made: made);
      addTearDown(controller.dispose);

      await controller.watch(_key, packets: first.stream);
      await controller.watch(_other, packets: second.stream);

      await controller.stop(_key);

      expect(controller.isWatching(_key), isFalse);
      expect(controller.isWatching(_other), isTrue);
      expect(made.first.stopped, 1);
      expect(made.last.stopped, 0);

      // The one still open is still read, and the one that was closed is not.
      for (final packet in _packetsFor()) {
        second.add(packet);
        first.add(packet);
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.decodedUnitsFor(_other), 1);
      expect(controller.receivedPacketsFor(_key), 0);
    });

    test('the stage falls back to the one left open', () async {
      final repository = _FakeRepository();
      final first = StreamController<IncomingVideoPacket>();
      final second = StreamController<IncomingVideoPacket>();
      addTearDown(first.close);
      addTearDown(second.close);
      final controller = _viewer(repository);
      addTearDown(controller.dispose);

      await controller.watch(_key, packets: first.stream);
      await controller.watch(_other, packets: second.stream);
      expect(controller.watching, _other);

      await controller.stop(_other);

      expect(controller.watching, _key);
    });

    test('stopping with no key ends everything', () async {
      final repository = _FakeRepository();
      final made = <_FakeDecoder>[];
      final controller = _viewer(repository, made: made);
      addTearDown(controller.dispose);

      await controller.watch(_key, packets: const Stream.empty());
      await controller.watch(_other, packets: const Stream.empty());

      await controller.stop();

      expect(controller.isWatching(_key), isFalse);
      expect(controller.isWatching(_other), isFalse);
      expect(controller.watching, isNull);
      // Leaving a room ends every session, not just the one on the stage.
      expect([for (final decoder in made) decoder.stopped], [1, 1]);
    });

    test('stopping one tells the connection layer which key', () async {
      final repository = _FakeRepository();
      final stopped = <GoLiveStreamKey>[];
      final controller = _viewer(repository, onWatchStopped: stopped.add);
      addTearDown(controller.dispose);

      await controller.watch(_key, packets: const Stream.empty());
      await controller.watch(_other, packets: const Stream.empty());

      await controller.stop(_key);

      // Once, for that key alone: the other connection stays up.
      expect(stopped, [_key]);
    });

    test('stopping everything tells the connection layer each key', () async {
      final repository = _FakeRepository();
      final stopped = <GoLiveStreamKey>[];
      final controller = _viewer(repository, onWatchStopped: stopped.add);
      addTearDown(controller.dispose);

      await controller.watch(_key, packets: const Stream.empty());
      await controller.watch(_other, packets: const Stream.empty());

      await controller.stop();

      expect(stopped, unorderedEquals([_key, _other]));
    });

    test('a fifth session is refused, and the refusal is reported', () async {
      final repository = _FakeRepository();
      final keys = _roomKeys();
      final controller = _viewer(repository);
      addTearDown(controller.dispose);

      for (final key in keys.take(4)) {
        expect(await controller.requestWatch(key), isTrue, reason: '$key');
      }
      expect(controller.isFull, isTrue);

      // The cap is ours and not Discord's, so the fifth is turned down here
      // rather than asked for and dropped on their side.
      expect(await controller.requestWatch(keys[4]), isFalse);
      expect(controller.refused, keys[4]);
      expect(repository.watched, [...keys.take(4)]);

      await controller.stop(keys.first);
      expect(await controller.requestWatch(keys[4]), isTrue);
      expect(controller.refused, isNull);
    });

    test('an answer that arrives late does not overtake a newer ask', () async {
      final repository = _FakeRepository();
      final first = StreamController<IncomingVideoPacket>();
      final second = StreamController<IncomingVideoPacket>();
      addTearDown(first.close);
      addTearDown(second.close);
      final controller = _viewer(repository);
      addTearDown(controller.dispose);

      await controller.requestWatch(_key);
      await controller.requestWatch(_other);

      // Discord opens the newer ask's connection first, and the older one's
      // second. Arriving is not asking: the stage belongs to whichever was
      // asked for last, not to whichever connection was opened last.
      await controller.attach(_other, packets: second.stream);
      await controller.attach(_key, packets: first.stream);

      expect(controller.watching, _other);
      expect(controller.isWatching(_key), isTrue);
    });

    test('a withdrawal is held per key', () async {
      final repository = _FakeRepository();
      final controller = _viewer(repository);
      addTearDown(controller.dispose);

      await controller.requestWatch(_key);
      await controller.requestWatch(_other);
      await controller.stop(_key);

      // One withdrawn, one still on its way: only the ask that was stopped
      // is dropped when Discord answers.
      expect(
        await controller.attach(_key, packets: const Stream.empty()),
        isFalse,
      );
      expect(
        await controller.attach(_other, packets: const Stream.empty()),
        isTrue,
      );
      expect(controller.isWatching(_key), isFalse);
      expect(controller.isWatching(_other), isTrue);
    });

    test('two asks withdrawn in turn are both dropped', () async {
      final repository = _FakeRepository();
      final controller = _viewer(repository);
      addTearDown(controller.dispose);

      await controller.requestWatch(_key);
      await controller.requestWatch(_other);
      await controller.stop(_key);
      await controller.stop(_other);

      // A single withdrawal remembered for the whole controller could only
      // hold the last one, and the first would take the stage after its
      // control had closed it.
      expect(
        await controller.attach(_key, packets: const Stream.empty()),
        isFalse,
      );
      expect(
        await controller.attach(_other, packets: const Stream.empty()),
        isFalse,
      );
      expect(controller.watching, isNull);
    });

    test(
      'a stream stopped while its decoder is opening is not watched',
      () async {
        final repository = _FakeRepository();
        final gate = Completer<void>();
        final decoder = _FakeDecoder(startGate: gate);
        final controller = StreamViewerController(
          repositoryProvider: () => repository,
          decoderFactory: () => decoder,
        );
        addTearDown(controller.dispose);

        await controller.requestWatch(_key);
        final attaching = controller.attach(
          _key,
          packets: const Stream.empty(),
        );
        await controller.stop(_key);
        gate.complete();

        expect(await attaching, isFalse);
        expect(controller.isWatching(_key), isFalse);
        expect(controller.watching, isNull);
        // Opened for a stream that was closed while it opened, and shut rather
        // than left running: one leaked decoder per withdrawal otherwise.
        expect(decoder.stopped, 1);
      },
    );

    test(
      'a connection reopened while one is opening does not replace it',
      () async {
        final repository = _FakeRepository();
        // Both held shut, so the order they open in is chosen here rather than
        // left to the microtask queue.
        final gates = <Completer<void>>[Completer<void>(), Completer<void>()];
        final made = <_FakeDecoder>[];
        final controller = StreamViewerController(
          repositoryProvider: () => repository,
          decoderFactory: () {
            final decoder = _FakeDecoder(startGate: gates[made.length]);
            made.add(decoder);
            return decoder;
          },
        );
        addTearDown(controller.dispose);
        expect(controller.isSupported, isTrue);
        made.clear();

        await controller.requestWatch(_key);
        final reopened = controller.attach(_key, packets: const Stream.empty());
        final reading = controller.attach(_key, packets: const Stream.empty());
        gates[1].complete();
        gates[0].complete();

        // One attach wins and the other decoder is stopped.
        expect([await reopened, await reading].where((ok) => ok), hasLength(1));
        expect(controller.isWatching(_key), isTrue);
        // The losing decoder is stopped.
        final stopped = [for (final decoder in made) decoder.stopped];
        expect(stopped.where((each) => each == 1), hasLength(1));
      },
    );
  });

  group('screen-share audio', () {
    test('a watched stream\'s sound plays', () async {
      final repository = _FakeRepository();
      final codecs = FakeVoiceOpusDecoderFactory();
      final controller = _viewer(repository, audioDecoderFactory: codecs);
      addTearDown(controller.dispose);
      final opus = _audioConnection();
      final heard = <VoiceRemotePcmFrame>[];
      final played = controller.audio.listen(heard.add);
      addTearDown(played.cancel);

      await controller.watch(
        _key,
        packets: const Stream.empty(),
        audio: opus.stream,
      );
      await Future<void>.delayed(Duration.zero);
      opus.add(_opusFrame('them', [7]));
      await Future<void>.delayed(Duration.zero);

      // Each watched session has its own audio decoder.
      expect(codecs.created, 1);
      expect(heard.single.userId, 'them');
      expect(heard.single.samples, [7]);
    });

    test('stopping the watch ends the sound with the session', () async {
      final repository = _FakeRepository();
      final codecs = FakeVoiceOpusDecoderFactory();
      final controller = _viewer(repository, audioDecoderFactory: codecs);
      addTearDown(controller.dispose);
      final opus = _audioConnection();
      final heard = <VoiceRemotePcmFrame>[];
      final played = controller.audio.listen(heard.add);
      addTearDown(played.cancel);

      await controller.watch(
        _key,
        packets: const Stream.empty(),
        audio: opus.stream,
      );
      await Future<void>.delayed(Duration.zero);
      opus.add(_opusFrame('them', [7]));
      await Future<void>.delayed(Duration.zero);
      expect(heard, hasLength(1));

      await controller.stop(_key);
      expect(codecs.disposed, 1);

      // Audio stops with the watched session.
      opus.add(_opusFrame('them', [8]));
      await Future<void>.delayed(Duration.zero);
      expect(heard, hasLength(1));
    });

    test('stopping one stream leaves the other audible', () async {
      final repository = _FakeRepository();
      final codecs = FakeVoiceOpusDecoderFactory();
      final controller = _viewer(repository, audioDecoderFactory: codecs);
      addTearDown(controller.dispose);
      final first = _audioConnection();
      final second = _audioConnection();
      final heard = <VoiceRemotePcmFrame>[];
      final played = controller.audio.listen(heard.add);
      addTearDown(played.cancel);

      await controller.watch(
        _key,
        packets: const Stream.empty(),
        audio: first.stream,
      );
      await controller.watch(
        _other,
        packets: const Stream.empty(),
        audio: second.stream,
      );
      await Future<void>.delayed(Duration.zero);

      await controller.stop(_key);
      first.add(_opusFrame('them', [1]));
      second.add(_opusFrame('u', [2]));
      await Future<void>.delayed(Duration.zero);

      expect(heard.map((frame) => frame.userId), ['u']);
      expect(heard.single.samples, [2]);
    });

    test('a suspended client goes on listening', () async {
      final repository = _FakeRepository();
      final codecs = FakeVoiceOpusDecoderFactory();
      final controller = _viewer(repository, audioDecoderFactory: codecs);
      addTearDown(controller.dispose);
      final opus = _audioConnection();
      final heard = <VoiceRemotePcmFrame>[];
      final played = controller.audio.listen(heard.add);
      addTearDown(played.cancel);

      await controller.watch(
        _key,
        packets: const Stream.empty(),
        audio: opus.stream,
      );
      await Future<void>.delayed(Duration.zero);

      // Suspension does not disable audio.
      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      opus.add(_opusFrame('them', [7]));
      await Future<void>.delayed(Duration.zero);

      expect(heard.single.samples, [7]);

      controller.setSuspended(false);
      await Future<void>.delayed(Duration.zero);
      opus.add(_opusFrame('them', [8]));
      await Future<void>.delayed(Duration.zero);
      expect(heard.map((frame) => frame.samples.single), [7, 8]);
      // Coming back reopens a picture decoder, never a second audio one.
      expect(codecs.created, 1);
    });
  });

  group('suspension', () {
    test(
      'a suspended session keeps its connection and draws nothing',
      () async {
        final repository = _FakeRepository();
        final packets = StreamController<IncomingVideoPacket>();
        addTearDown(packets.close);
        final made = <_FakeDecoder>[];
        final controller = _viewer(repository, made: made);
        addTearDown(controller.dispose);
        await controller.watch(_key, packets: packets.stream);
        // Drawing, while the window is being looked at: what the room reads is
        // this decoder's pictures.
        final drawn = <DecodedVideoFrame>[];
        final frames = controller.framesFor(_key).listen(drawn.add);
        addTearDown(frames.cancel);
        made.single.emit(_picture);
        await Future<void>.delayed(Duration.zero);
        expect(drawn, hasLength(1));
        for (final packet in _packetsFor()) {
          packets.add(packet);
        }
        await Future<void>.delayed(Duration.zero);
        expect(controller.decodedUnits, 1);

        controller.setSuspended(true);
        await Future<void>.delayed(Duration.zero);
        expect(controller.isSuspended, isTrue);

        // Nothing on Discord's side is torn down and nothing is withdrawn: the
        // room goes on showing the stream it was showing.
        expect(controller.isWatching(_key), isTrue);
        expect(controller.watching, _key);
        expect(repository.watched, [_key]);
        expect(repository.ended, isEmpty);
        // What turns packets into pictures is what goes.
        expect(made.single.stopped, 1);

        // The room resubscribes when what it draws from changes, which is what
        // being let go does to a decoder.
        await frames.cancel();
        drawn.clear();
        final afterSuspension = controller.framesFor(_key).listen(drawn.add);
        addTearDown(afterSuspension.cancel);
        for (final packet in _packetsFor()) {
          packets.add(packet);
        }
        await Future<void>.delayed(Duration.zero);

        // Still arriving, and still counted, so a stream that is arriving reads
        // as arriving. Drawn nothing: the packets stop at the subscription that
        // keeps the connection alive.
        expect(controller.receivedPacketsFor(_key), 4);
        expect(controller.decodedUnitsFor(_key), 1);
        expect(made.single.submitted, hasLength(1));
        expect(drawn, isEmpty);

        // Focus events arrive in bursts. A repeat is not news to the room, and
        // a decoder cannot be let go twice.
        var notified = 0;
        controller.addListener(() => notified++);
        controller.setSuspended(true);
        await Future<void>.delayed(Duration.zero);
        expect(notified, 0);
        expect(made.single.stopped, 1);
      },
    );

    test('every open session is suspended, and every one comes back', () async {
      final repository = _FakeRepository();
      final first = StreamController<IncomingVideoPacket>();
      final second = StreamController<IncomingVideoPacket>();
      addTearDown(first.close);
      addTearDown(second.close);
      final made = <_FakeDecoder>[];
      final controller = _viewer(repository, made: made);
      addTearDown(controller.dispose);
      await controller.watch(_key, packets: first.stream);
      await controller.watch(_other, packets: second.stream);

      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      expect([for (final decoder in made) decoder.stopped], [1, 1]);

      controller.setSuspended(false);
      await Future<void>.delayed(Duration.zero);
      // Two let go, two opened in their place: one decoder per session, as
      // before, and not one shared between them.
      expect(made, hasLength(4));
      expect([for (final decoder in made.skip(2)) decoder.started], [1, 1]);
    });

    test('coming back reattaches a decoder without asking again', () async {
      final repository = _FakeRepository();
      final packets = StreamController<IncomingVideoPacket>();
      addTearDown(packets.close);
      final made = <_FakeDecoder>[];
      final controller = _viewer(repository, made: made);
      addTearDown(controller.dispose);
      await controller.watch(_key, packets: packets.stream);
      // Half a picture, as a window going away mid-picture leaves it: the
      // parameter set and the first fragment of the slice behind it. A slice
      // this size is what makes the packetiser fragment one at all.
      for (final packet in _packetsFor(sliceLength: 1400).take(2)) {
        packets.add(packet);
      }
      await Future<void>.delayed(Duration.zero);

      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      controller.setSuspended(false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.isSuspended, isFalse);

      // A new decoder for the session that never went away. Discord was not
      // asked again, so there is no handshake and no new endpoint: the
      // connection was kept open the whole time.
      expect(made, hasLength(2));
      expect(made.last.started, 1);
      expect(repository.watched, [_key]);
      expect(controller.isRequested(_key), isFalse);
      expect(controller.watching, _key);

      // The rest of the picture that was arriving when the window went away.
      // It is dropped: a depacketiser that remembered the first half would
      // splice the two into one, and what comes back waits for the sender's
      // next keyframe instead (ADR-0003).
      packets.add(_packetsFor(sliceLength: 1400).last);
      await Future<void>.delayed(Duration.zero);
      expect(controller.receivedPacketsFor(_key), 3);
      expect(controller.decodedUnitsFor(_key), 0);

      // What the room draws from is the new decoder's pictures again.
      final drawn = <DecodedVideoFrame>[];
      final frames = controller.framesFor(_key).listen(drawn.add);
      addTearDown(frames.cancel);
      made.last.emit(_picture);
      await Future<void>.delayed(Duration.zero);
      expect(drawn, hasLength(1));

      // A whole picture, and the session draws again.
      for (final packet in _packetsFor(sliceLength: 1400)) {
        packets.add(packet);
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.decodedUnitsFor(_key), 1);
      expect(made.last.submitted, hasLength(1));
      expect(made.first.submitted, isEmpty);

      // A second focus event opens nothing further.
      controller.setSuspended(false);
      await Future<void>.delayed(Duration.zero);
      expect(made, hasLength(2));
    });

    test(
      'a connection that arrives while suspended waits for the window',
      () async {
        final repository = _FakeRepository();
        final packets = StreamController<IncomingVideoPacket>();
        addTearDown(packets.close);
        final made = <_FakeDecoder>[];
        final controller = _viewer(repository, made: made);
        addTearDown(controller.dispose);

        controller.setSuspended(true);
        await Future<void>.delayed(Duration.zero);
        expect(await controller.watch(_key, packets: packets.stream), isTrue);

        // Asked for and arriving, with nothing decoding it: a decoder opened
        // for a window that is not looking would only be let go of again.
        expect(controller.isWatching(_key), isTrue);
        expect(made, isEmpty);

        for (final packet in _packetsFor()) {
          packets.add(packet);
        }
        await Future<void>.delayed(Duration.zero);
        expect(controller.receivedPacketsFor(_key), 2);
        expect(controller.decodedUnitsFor(_key), 0);

        controller.setSuspended(false);
        await Future<void>.delayed(Duration.zero);
        expect(made, hasLength(1));
        for (final packet in _packetsFor()) {
          packets.add(packet);
        }
        await Future<void>.delayed(Duration.zero);
        expect(controller.decodedUnitsFor(_key), 1);
      },
    );

    test(
      'the window going away again shuts the decoder it was opening',
      () async {
        final repository = _FakeRepository();
        final packets = StreamController<IncomingVideoPacket>();
        addTearDown(packets.close);
        final gate = Completer<void>();
        final made = <_FakeDecoder>[];
        final controller = StreamViewerController(
          repositoryProvider: () => repository,
          decoderFactory: () {
            // The decoder a resume opens is held shut, so the window can go
            // away again while it is opening. The first one is the session's.
            final decoder = _FakeDecoder(startGate: made.isEmpty ? null : gate);
            made.add(decoder);
            return decoder;
          },
        );
        addTearDown(controller.dispose);
        expect(controller.isSupported, isTrue);
        made.clear();

        await controller.watch(_key, packets: packets.stream);
        controller.setSuspended(true);
        await Future<void>.delayed(Duration.zero);
        controller.setSuspended(false);
        // Gone again before the decoder has finished opening.
        controller.setSuspended(true);
        gate.complete();
        await Future<void>.delayed(Duration.zero);

        // Opened for a window that is not looking any more, and shut rather
        // than left decoding into it.
        expect(made, hasLength(2));
        expect(made.last.started, 1);
        expect(made.last.stopped, 1);
        expect(controller.isSuspended, isTrue);
      },
    );

    test(
      'the window going away while a connection is arriving leaves it undecoded',
      () async {
        final repository = _FakeRepository();
        final packets = StreamController<IncomingVideoPacket>();
        addTearDown(packets.close);
        final gate = Completer<void>();
        final made = <_FakeDecoder>[];
        final controller = StreamViewerController(
          repositoryProvider: () => repository,
          decoderFactory: () {
            // The decoder the arriving connection opens is held shut, so the
            // window can go away before it has finished opening.
            final decoder = _FakeDecoder(startGate: made.isEmpty ? gate : null);
            made.add(decoder);
            return decoder;
          },
        );
        addTearDown(controller.dispose);
        expect(controller.isSupported, isTrue);
        made.clear();

        await controller.requestWatch(_key);
        final attaching = controller.attach(_key, packets: packets.stream);
        // Far enough in for the decoder to be opening, which is where the
        // window going away catches it.
        await Future<void>.delayed(Duration.zero);
        controller.setSuspended(true);
        gate.complete();
        expect(await attaching, isTrue);

        // Arriving, and not decoding. The session keeps the connection it was
        // given, and the decoder that opened for it is handed straight back:
        // suspending could not reach a key that was not being held yet.
        expect(controller.isWatching(_key), isTrue);
        expect(made, hasLength(1));
        expect(made.single.started, 1);
        expect(made.single.stopped, 1);

        for (final packet in _packetsFor()) {
          packets.add(packet);
        }
        await Future<void>.delayed(Duration.zero);
        expect(controller.receivedPacketsFor(_key), 2);
        expect(controller.decodedUnitsFor(_key), 0);

        // And it decodes as soon as the window is back.
        controller.setSuspended(false);
        await Future<void>.delayed(Duration.zero);
        for (final packet in _packetsFor()) {
          packets.add(packet);
        }
        await Future<void>.delayed(Duration.zero);
        expect(controller.decodedUnitsFor(_key), 1);
      },
    );

    test('two resumes in a row leave one decoder, not two', () async {
      final repository = _FakeRepository();
      final packets = StreamController<IncomingVideoPacket>();
      addTearDown(packets.close);
      final gates = [Completer<void>(), Completer<void>()];
      final made = <_FakeDecoder>[];
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () {
          // The session's own decoder opens at once; the two a burst of focus
          // events races to open are held shut, so both are in flight at the
          // same moment.
          final decoder = switch (made.length) {
            0 => _FakeDecoder(),
            1 => _FakeDecoder(startGate: gates[0]),
            _ => _FakeDecoder(startGate: gates[1]),
          };
          made.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      expect(controller.isSupported, isTrue);
      made.clear();

      await controller.watch(_key, packets: packets.stream);
      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      // A burst: away, back, away, back again. Each call starts its work at
      // once and leaves it at the first await, so both openings are in flight
      // here rather than one after the other.
      controller.setSuspended(false);
      controller.setSuspended(true);
      controller.setSuspended(false);
      // Both open, the second of them first.
      gates[1].complete();
      gates[0].complete();
      await Future<void>.delayed(Duration.zero);

      // One decoder for the session, and the one that lost is shut rather
      // than left decoding with nobody holding it.
      expect(made, hasLength(3));
      expect([made[1].stopped, made[2].stopped], [1, 0]);

      // The room draws from the one that is left, and nothing reaches it from
      // the one that was shut.
      final drawn = <DecodedVideoFrame>[];
      final frames = controller.framesFor(_key).listen(drawn.add);
      addTearDown(frames.cancel);
      made[1].emit(_picture);
      made[2].emit(_picture);
      await Future<void>.delayed(Duration.zero);
      expect(drawn, hasLength(1));

      for (final packet in _packetsFor()) {
        packets.add(packet);
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.decodedUnitsFor(_key), 1);
      expect(made[1].submitted, isEmpty);
      expect(made[2].submitted, hasLength(1));
    });

    test('stopping a suspended session shuts nothing twice', () async {
      final repository = _FakeRepository();
      final packets = StreamController<IncomingVideoPacket>();
      addTearDown(packets.close);
      final made = <_FakeDecoder>[];
      final controller = _viewer(repository, made: made);
      addTearDown(controller.dispose);
      await controller.watch(_key, packets: packets.stream);

      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      await controller.stop(_key);

      expect(controller.isOpen(_key), isFalse);
      expect(controller.isWatching(_key), isFalse);
      // Let go once, by the suspension. A stop that shut it again would be
      // shutting a decoder this controller is no longer holding.
      expect(made.single.stopped, 1);
      expect(controller.watching, isNull);
    });

    test('suspending a session ends nothing on Discord\'s side', () async {
      final repository = _FakeRepository();
      final packets = StreamController<IncomingVideoPacket>();
      addTearDown(packets.close);
      final made = <_FakeDecoder>[];
      final controller = _viewer(repository, made: made);
      addTearDown(controller.dispose);
      await controller.watch(_key, packets: packets.stream);

      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);

      // The session stops drawing and keeps its place; nothing is ended on
      // Discord's side (ADR-0003).
      expect(controller.isWatching(_key), isTrue);
      expect(made.single.stopped, 1);
      expect(repository.ended, isEmpty);

      controller.setSuspended(false);
      await Future<void>.delayed(Duration.zero);
      for (final packet in _packetsFor()) {
        packets.add(packet);
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.decodedUnitsFor(_key), 1);
      expect(controller.watching, _key);
    });

    test('a decoder that will not reopen is reported, then retried', () async {
      final repository = _FakeRepository();
      final packets = StreamController<IncomingVideoPacket>();
      addTearDown(packets.close);
      final made = <_FakeDecoder>[];
      var refuse = false;
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () {
          final decoder = _FakeDecoder(failStart: refuse);
          made.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      expect(controller.isSupported, isTrue);
      made.clear();

      await controller.watch(_key, packets: packets.stream);
      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      refuse = true;
      controller.setSuspended(false);
      await Future<void>.delayed(Duration.zero);

      // The session is not thrown away because a decoder would not open: the
      // connection is still there, and the room is told why there is no
      // picture.
      expect(controller.errorFor(_key), isNotNull);
      expect(controller.isWatching(_key), isTrue);
      expect(made, hasLength(2));

      // Another return to the window is a clean attempt.
      refuse = false;
      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      controller.setSuspended(false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.errorFor(_key), isNull);

      for (final packet in _packetsFor()) {
        packets.add(packet);
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.decodedUnitsFor(_key), 1);
    });

    test('disposing while a decoder is reopening shuts it', () async {
      final repository = _FakeRepository();
      final packets = StreamController<IncomingVideoPacket>();
      addTearDown(packets.close);
      final gate = Completer<void>();
      final made = <_FakeDecoder>[];
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoderFactory: () {
          // The decoder the resume opens is held shut, so the controller can
          // be disposed while it is opening.
          final decoder = _FakeDecoder(startGate: made.isEmpty ? null : gate);
          made.add(decoder);
          return decoder;
        },
      );
      expect(controller.isSupported, isTrue);
      made.clear();

      await controller.watch(_key, packets: packets.stream);
      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      controller.setSuspended(false);
      // Disposed here rather than in a teardown, because this test is about
      // what the disposal itself does.
      controller.dispose();
      gate.complete();
      await Future<void>.delayed(Duration.zero);

      // Opened for a controller that is already gone, and handed back rather
      // than left decoding with nobody holding it.
      expect(made, hasLength(2));
      expect(made.last.started, 1);
      expect(made.last.stopped, 1);
    });
  });
}

/// A controller that makes one decoder per session, recording them in [made]
/// when [made] is given.
///
/// Whether this build can decode at all is asked of a decoder that no session
/// reads from, so the list is emptied once that has been asked: what a test
/// counts afterwards is sessions only.
StreamViewerController _viewer(
  GoLiveRepository repository, {
  List<_FakeDecoder>? made,
  VoiceOpusDecoderFactory? audioDecoderFactory,
  void Function(GoLiveStreamKey key)? onWatchStopped,
}) {
  final controller = StreamViewerController(
    repositoryProvider: () => repository,
    decoderFactory: () {
      final decoder = _FakeDecoder();
      made?.add(decoder);
      return decoder;
    },
    onWatchStopped: onWatchStopped,
    audioDecoderFactory: audioDecoderFactory,
  );
  expect(controller.isSupported, isTrue);
  made?.clear();
  return controller;
}

/// Five streams in one room, which is one more than this client will hold.
List<GoLiveStreamKey> _roomKeys() => [
  for (var index = 0; index < 5; index++)
    GoLiveStreamKey.call(channelId: 'dm-1', userId: 'u$index'),
];

final class _FakeDecoder implements VideoDecoderService {
  _FakeDecoder({this.supported = true, this.failStart = false, this.startGate});

  final bool supported;
  final bool failStart;

  /// Held shut so a test can act while a decoder is still opening, which is
  /// the window every ask can be withdrawn in.
  final Completer<void>? startGate;
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  final List<Uint8List> submitted = [];
  int started = 0;
  int stopped = 0;

  void emit(DecodedVideoFrame frame) => _frames.add(frame);

  Future<void> close() => _frames.close();

  @override
  bool get isSupported => supported;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Stream<int> get droppedAccessUnits => const Stream.empty();

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

final class _FakeRepository implements GoLiveRepository {
  _FakeRepository({this.failWatch = false});

  final bool failWatch;
  final List<GoLiveStreamKey> watched = [];

  /// What this client ended on Discord's side. Suspension must leave it
  /// empty: what is let go is this client's decoder, not the stream.
  final List<GoLiveStreamKey> ended = [];

  /// Watches this client withdrew on Discord's side.
  final List<GoLiveStreamKey> stoppedWatching = [];

  @override
  Map<String, GoLiveStream> get streams => const {};

  @override
  Stream<GoLiveStream> get updates => const Stream.empty();

  @override
  Stream<GoLiveServer> get servers => const Stream.empty();

  @override
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) async => _key;

  @override
  Future<void> watchStream(GoLiveStreamKey key) async {
    if (failWatch) throw StateError('refused');
    watched.add(key);
  }

  @override
  Future<void> pingStream(GoLiveStreamKey key) async {}

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async {}

  @override
  Future<void> endStream(GoLiveStreamKey key) async => ended.add(key);

  @override
  Future<void> stopWatching(GoLiveStreamKey key) async =>
      stoppedWatching.add(key);
}
