import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = GoLiveStreamKey.call(channelId: 'dm-1', userId: 'them');

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

void main() {
  test('a build that cannot decode watches nothing', () async {
    final repository = _FakeRepository();
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoder: _FakeDecoder(supported: false),
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
      decoder: _FakeDecoder(),
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
      decoder: decoder,
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

  test('a picture still arriving is not submitted yet', () async {
    final repository = _FakeRepository();
    final decoder = _FakeDecoder();
    final packets = StreamController<IncomingVideoPacket>();
    addTearDown(packets.close);
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoder: decoder,
    );
    addTearDown(controller.dispose);
    await controller.watch(_key, packets: packets.stream);

    packets.add(_packetsFor().first);
    await Future<void>.delayed(Duration.zero);

    expect(controller.receivedPackets, 1);
    expect(controller.decodedUnits, 0);
    expect(decoder.submitted, isEmpty);
  });

  test('stopping releases the decoder and forgets the counts', () async {
    final repository = _FakeRepository();
    final decoder = _FakeDecoder();
    final packets = StreamController<IncomingVideoPacket>();
    addTearDown(packets.close);
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoder: decoder,
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

  test('watching a second stream replaces the first', () async {
    final repository = _FakeRepository();
    final decoder = _FakeDecoder();
    final first = StreamController<IncomingVideoPacket>();
    final second = StreamController<IncomingVideoPacket>();
    addTearDown(first.close);
    addTearDown(second.close);
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoder: decoder,
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
    // The stream that was replaced is no longer read.
    expect(controller.receivedPackets, 0);
  });

  test('a refused watch is reported and starts no decoder', () async {
    final repository = _FakeRepository(failWatch: true);
    final decoder = _FakeDecoder();
    final controller = StreamViewerController(
      repositoryProvider: () => repository,
      decoder: decoder,
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
      decoder: decoder,
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
      decoder: _FakeDecoder(),
    );
    addTearDown(controller.dispose);
    await controller.watch(_key, packets: packets.stream);

    packets.addError(StateError('connection lost'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.error, isNotNull);
  });

  test('the frames it exposes are the decoder\'s own', () async {
    final decoder = _FakeDecoder();
    final controller = StreamViewerController(
      repositoryProvider: () => _FakeRepository(),
      decoder: decoder,
    );
    addTearDown(controller.dispose);
    addTearDown(decoder.close);

    final seen = <DecodedVideoFrame>[];
    final subscription = controller.frames.listen(seen.add);
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
        decoder: decoder,
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

    test('attaching decodes without asking a second time', () async {
      final repository = _FakeRepository();
      final decoder = _FakeDecoder();
      final controller = StreamViewerController(
        repositoryProvider: () => repository,
        decoder: decoder,
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
        decoder: _FakeDecoder(),
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
        decoder: _FakeDecoder(supported: false),
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
        decoder: _FakeDecoder(),
      );
      addTearDown(controller.dispose);

      await controller.requestWatch(_key);
      await controller.stop();

      expect(controller.requested, isNull);
    });

    test(
      'a decoder that will not start reports rather than half-attaches',
      () async {
        final controller = StreamViewerController(
          repositoryProvider: () => _FakeRepository(),
          decoder: _FakeDecoder(failStart: true),
        );
        addTearDown(controller.dispose);

        expect(
          await controller.attach(_key, packets: const Stream.empty()),
          isFalse,
        );
        expect(controller.watching, isNull);
        expect(controller.error, isNotNull);
      },
    );
  });
}

final class _FakeDecoder implements VideoDecoderService {
  _FakeDecoder({this.supported = true, this.failStart = false});

  final bool supported;
  final bool failStart;
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
  Future<void> start() async {
    if (failStart) throw StateError('no decoder');
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
  Future<void> endStream(GoLiveStreamKey key) async {}
}
