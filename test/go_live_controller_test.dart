import 'dart:async';

import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

/// The controller over the machine's one capture module, with the fake
/// encoder behind it.
GoLiveController _controller(
  _FakeRepository? repository, {
  _FakeEncoder? encoder,
  Duration pingInterval = const Duration(seconds: 30),
}) {
  final controller = GoLiveController(
    repositoryProvider: () => repository,
    capture: VideoCaptureHub(encoder: encoder ?? _FakeEncoder()),
    pingInterval: pingInterval,
  )..reconcile();
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  test('a transport that cannot stream offers nothing', () async {
    final controller = _controller(null);

    expect(controller.isSupported, isFalse);
    expect(
      await controller.start(sourceId: 'screen-1', channelId: 'voice-1'),
      isFalse,
    );
    expect(await controller.watch(_key), isFalse);
  });

  test('captures before announcing, and pings while live', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final encoder = _FakeEncoder();
    final controller = _controller(
      repository,
      encoder: encoder,
      pingInterval: const Duration(milliseconds: 10),
    );

    expect(
      await controller.start(
        sourceId: 'screen-1',
        channelId: 'voice-1',
        guildId: 'guild-1',
      ),
      isTrue,
    );

    // A stream announced with nothing behind it shows viewers a black
    // rectangle, so the capture goes first. And the capture is the capture
    // module's, which is the only thing that duplicates the display.
    expect(encoder.started, 1);
    expect(controller.streamKey, _key);
    expect(controller.status, GoLiveStatus.creating);

    repository.announce(const GoLiveStream(key: _key, viewerIds: ['viewer-1']));
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, GoLiveStatus.connecting);
    expect(controller.viewerIds, ['viewer-1']);

    repository.assign(
      const GoLiveServer(key: _key, endpoint: 'stream.discord.gg', token: 't'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, GoLiveStatus.live);
    expect(controller.server?.endpoint, 'stream.discord.gg');
    expect(controller.isStreaming, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repository.pings, isNotEmpty);

    await controller.stop();
    expect(encoder.stopped, 1);
    expect(repository.ended, [_key]);
    expect(controller.status, GoLiveStatus.idle);
    expect(controller.streamKey, isNull);
    expect(controller.viewerIds, isEmpty);

    final pings = repository.pings.length;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // The ping stops with the stream.
    expect(repository.pings.length, pings);
  });

  test('an encoder that fails leaves nothing announced', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final controller = _controller(
      repository,
      encoder: _FakeEncoder()..failStart = true,
    );

    expect(
      await controller.start(sourceId: 'screen-1', channelId: 'voice-1'),
      isFalse,
    );

    // The capture is the picture. Announcing a stream with nothing behind it
    // shows every viewer a black rectangle.
    expect(controller.status, GoLiveStatus.failure);
    expect(controller.error, isNotNull);
    expect(repository.started, isEmpty);
  });

  test('a refused stream stops the capture behind it', () async {
    final repository = _FakeRepository(failStart: true);
    addTearDown(repository.close);
    final encoder = _FakeEncoder();
    final controller = _controller(repository, encoder: encoder);

    expect(
      await controller.start(sourceId: 'screen-1', channelId: 'voice-1'),
      isFalse,
    );

    expect(controller.status, GoLiveStatus.failure);
    expect(encoder.stopped, 1);
  });

  test('a second start while one is running is refused', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final encoder = _FakeEncoder();
    final controller = _controller(repository, encoder: encoder);

    await controller.start(sourceId: 'screen-1', channelId: 'voice-1');
    expect(
      await controller.start(sourceId: 'screen-2', channelId: 'voice-1'),
      isFalse,
    );

    // One capture, still the first one's.
    expect(encoder.started, 1);
  });

  test('a share while the camera holds the capture is refused', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    // One capture module, shared the way the app shares it: the camera and
    // the share are clients of the same one.
    final encoder = _FakeEncoder(cameras: const ['Webcam']);
    final capture = VideoCaptureHub(encoder: encoder);
    await capture.startCamera();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      capture: capture,
    )..reconcile();
    addTearDown(controller.dispose);

    expect(await controller.start(channelId: 'voice-1'), isFalse);

    // The capture module is the arbiter: with the camera on it, a share is
    // not started on the side and nothing is announced.
    expect(encoder.started, 1);
    expect(encoder.startedSettings.single.source, VideoCaptureSource.camera);
    expect(repository.started, isEmpty);
    expect(controller.status, GoLiveStatus.failure);
    expect(controller.error, isA<VideoEncoderException>());

    // And the camera itself is undisturbed.
    expect(capture.isCapturing, isTrue);
    expect(capture.settings!.source, VideoCaptureSource.camera);
    await capture.stop();
  });

  test('pausing and resuming report themselves', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final controller = _controller(repository);

    // Nothing to pause before a stream exists.
    expect(await controller.setPaused(paused: true), isFalse);

    await controller.start(
      sourceId: 'screen-1',
      channelId: 'voice-1',
      guildId: 'guild-1',
    );
    repository.assign(const GoLiveServer(key: _key, endpoint: 'e', token: 't'));
    await Future<void>.delayed(Duration.zero);

    expect(await controller.setPaused(paused: true), isTrue);
    expect(controller.status, GoLiveStatus.paused);
    expect(await controller.setPaused(paused: false), isTrue);
    expect(controller.status, GoLiveStatus.live);
    // The unpause the create is followed by comes first: Discord's own
    // clients send one, and a stream that never does has its RTC session
    // refused.
    expect(repository.pauses, [false, true, false]);
  });

  test('a pause somebody else applied is followed', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final controller = _controller(repository);
    await controller.start(
      sourceId: 'screen-1',
      channelId: 'voice-1',
      guildId: 'guild-1',
    );
    repository.assign(const GoLiveServer(key: _key, endpoint: 'e', token: 't'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, GoLiveStatus.live);

    // Discord pauses a stream on its own when the sender falls behind.
    repository.announce(const GoLiveStream(key: _key, isPaused: true));
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, GoLiveStatus.paused);

    repository.announce(const GoLiveStream(key: _key));
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, GoLiveStatus.live);
  });

  test('a refused pause is reported without changing the state', () async {
    final repository = _FakeRepository(failPause: true);
    addTearDown(repository.close);
    final controller = _controller(repository);
    await controller.start(
      sourceId: 'screen-1',
      channelId: 'voice-1',
      guildId: 'guild-1',
    );
    repository.assign(const GoLiveServer(key: _key, endpoint: 'e', token: 't'));
    await Future<void>.delayed(Duration.zero);

    expect(await controller.setPaused(paused: true), isFalse);

    expect(controller.status, GoLiveStatus.live);
    expect(controller.error, isNotNull);
  });

  test('somebody else\'s stream is ignored by this controller', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final controller = _controller(repository);
    await controller.start(
      sourceId: 'screen-1',
      channelId: 'voice-1',
      guildId: 'guild-1',
    );

    const other = GoLiveStreamKey.call(channelId: 'dm-1', userId: 'them');
    repository
      ..announce(const GoLiveStream(key: other, viewerIds: ['a', 'b']))
      ..assign(const GoLiveServer(key: other, endpoint: 'e', token: 't'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.viewerIds, isEmpty);
    expect(controller.server, isNull);
    expect(controller.status, GoLiveStatus.creating);
  });

  test('watching somebody else asks for it', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final controller = _controller(repository);

    const other = GoLiveStreamKey.call(channelId: 'dm-1', userId: 'them');
    expect(await controller.watch(other), isTrue);
    expect(repository.watched, [other]);

    repository.failWatch = true;
    expect(await controller.watch(other), isFalse);
    expect(controller.error, isNotNull);
  });

  test('stopping what was never started tears nothing down', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final controller = _controller(repository);

    await controller.stop();

    expect(repository.ended, isEmpty);
    expect(controller.status, GoLiveStatus.idle);
  });

  test('an end Discord refuses still releases the capture', () async {
    final repository = _FakeRepository(failEnd: true);
    addTearDown(repository.close);
    final encoder = _FakeEncoder();
    final controller = _controller(repository, encoder: encoder);
    await controller.start(
      sourceId: 'screen-1',
      channelId: 'voice-1',
      guildId: 'guild-1',
    );

    await controller.stop();

    expect(controller.error, isNotNull);
    expect(encoder.stopped, 1);
    expect(controller.streamKey, isNull);
  });

  test('a capture that will not stop does not mask the reason', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final controller = _controller(
      repository,
      encoder: _FakeEncoder()..failStop = true,
    );
    await controller.start(
      sourceId: 'screen-1',
      channelId: 'voice-1',
      guildId: 'guild-1',
    );

    await controller.stop();

    expect(controller.status, GoLiveStatus.idle);
    expect(controller.error, isNull);
  });

  test('swapping the transport rebinds the streams', () async {
    var repository = _FakeRepository();
    final first = repository;
    addTearDown(first.close);
    final controller = _controller(repository);

    repository = _FakeRepository();
    addTearDown(() => repository.close());
    controller
      ..reconcile()
      ..reconcile();

    expect(controller.isSupported, isTrue);
  });

  group('sharing without picking a source', () {
    test('shares the primary display the capture takes by default', () async {
      final encoder = _FakeEncoder();
      final controller = _controller(_FakeRepository(), encoder: encoder);

      expect(await controller.start(channelId: 'voice-1'), isTrue);

      // Nothing is named, and the capture module takes the primary display
      // for itself.
      expect(encoder.started, 1);
      expect(encoder.startedSettings.single.displayIndex, 0);
    });

    test('offers a screen per display the capture module can capture', () {
      final controller = _controller(_FakeRepository());

      // Two, from the capture module. Asking a capture library instead opens
      // duplications to build thumbnails with, which is the same conflict.
      expect(controller.displays.map((display) => display.sourceId), [
        'screen:0:0',
        'screen:1:0',
      ]);
    });

    test('a chosen screen is the one the capture takes', () async {
      final encoder = _FakeEncoder();
      final controller = _controller(_FakeRepository(), encoder: encoder);

      await controller.start(channelId: 'voice-1', sourceId: 'screen:2:0');

      // The picker names a screen by its index; the capture addresses
      // displays by the same index, and sharing the second monitor used to
      // encode the first.
      expect(encoder.startedSettings.single.displayIndex, 2);
    });
  });
}

final class _FakeEncoder implements VideoEncoderService {
  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  _FakeEncoder({this.cameras = const []});

  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();
  final List<String> cameras;
  final List<VideoEncoderSettings> startedSettings = [];
  VideoEncoderSettings? settings;
  bool failStart = false;
  bool failStop = false;
  int started = 0;
  int stopped = 0;

  @override
  bool get isSupported => true;

  @override
  int get displayCount => 2;

  @override
  List<String> get cameraNames => cameras;

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start(VideoEncoderSettings requested) async {
    if (failStart) throw StateError('no encoder');
    started++;
    settings = requested;
    startedSettings.add(requested);
  }

  @override
  Future<void> setPaused({required bool paused}) async {}

  @override
  Future<void> requestKeyframe() async {}

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('already gone');
    stopped++;
  }
}

final class _FakeRepository implements GoLiveRepository {
  _FakeRepository({
    this.failStart = false,
    this.failPause = false,
    this.failEnd = false,
  });

  final bool failStart;
  final bool failPause;
  final bool failEnd;
  bool failWatch = false;

  final StreamController<GoLiveStream> _updates = StreamController.broadcast();
  final StreamController<GoLiveServer> _servers = StreamController.broadcast();
  final List<String> started = [];
  final List<GoLiveStreamKey> watched = [];
  final List<GoLiveStreamKey> pings = [];
  final List<GoLiveStreamKey> ended = [];
  final List<bool> pauses = [];

  void announce(GoLiveStream stream) => _updates.add(stream);

  void assign(GoLiveServer server) => _servers.add(server);

  @override
  Map<String, GoLiveStream> get streams => const {};

  @override
  Stream<GoLiveStream> get updates => _updates.stream;

  @override
  Stream<GoLiveServer> get servers => _servers.stream;

  @override
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) async {
    if (failStart) throw StateError('refused');
    started.add(channelId);
    return guildId == null
        ? GoLiveStreamKey.call(channelId: channelId, userId: 'me')
        : GoLiveStreamKey.guild(
            guildId: guildId,
            channelId: channelId,
            userId: 'me',
          );
  }

  @override
  Future<void> watchStream(GoLiveStreamKey key) async {
    if (failWatch) throw StateError('refused');
    watched.add(key);
  }

  @override
  Future<void> pingStream(GoLiveStreamKey key) async => pings.add(key);

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async {
    if (failPause) throw StateError('refused');
    pauses.add(paused);
  }

  @override
  Future<void> endStream(GoLiveStreamKey key) async {
    if (failEnd) throw StateError('refused');
    ended.add(key);
  }

  Future<void> close() async {
    await _updates.close();
    await _servers.close();
  }
}
