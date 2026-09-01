import 'dart:async';

import 'dart:typed_data';

import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_service.dart';
import 'package:flucord/src/data/discord/go_live_media_plane.dart';
import 'package:flucord/src/data/discord/go_live_sender.dart';
import 'package:flucord/src/domain/go_live_media.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/stream_quality.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_video_encoder.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

const _credentials = VoiceServerCredentials(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
  sessionId: 'session-1',
  token: 'stream-token',
  endpoint: 'stream.discord.gg',
);

/// The controller over the machine's one capture module, with the fake
/// encoder behind it and the sender endpoints under the test's control.
GoLiveController _controller(
  _FakeRepository? repository, {
  FakeVideoEncoder? encoder,
  _FakePlane? plane,
  StreamController<DiscordSenderEndpoint>? endpoints,
  List<GoLiveStreamKey>? ready,
  Duration pingInterval = const Duration(seconds: 30),
}) {
  final media = plane ?? _FakePlane();
  final controller = GoLiveController(
    repositoryProvider: () => repository,
    capture: VideoCaptureHub(
      encoder: encoder ?? FakeVideoEncoder(displays: 2),
      shareFrames: media,
    ),
    media: media,
    senderEndpoints: endpoints?.stream,
    onSenderReady: ready?.add,
    pingInterval: pingInterval,
  )..reconcile();
  addTearDown(controller.dispose);
  return controller;
}

/// Starts a stream and hands the controller its sender endpoint.
Future<_FakeSender> _sending(
  GoLiveController controller,
  _FakePlane plane,
  StreamController<DiscordSenderEndpoint> endpoints,
) async {
  await controller.start(channelId: 'voice-1', guildId: 'guild-1');
  endpoints.add((key: _key, credentials: _credentials));
  await Future<void>.delayed(Duration.zero);
  return plane.opened.single;
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
    final encoder = FakeVideoEncoder(displays: 2);
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
    expect(encoder.started, hasLength(1));
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

  test(
    'the sender endpoint opens a Sender with the running settings',
    () async {
      final repository = _FakeRepository();
      addTearDown(repository.close);
      final encoder = FakeVideoEncoder(displays: 2);
      final plane = _FakePlane();
      final endpoints = StreamController<DiscordSenderEndpoint>.broadcast();
      final ready = <GoLiveStreamKey>[];
      final controller = _controller(
        repository,
        encoder: encoder,
        plane: plane,
        endpoints: endpoints,
        ready: ready,
      );

      final sender = await _sending(controller, plane, endpoints);

      // The capture was opened where the plane takes frames, and the Sender
      // with what the capture is running at.
      expect(encoder.frameSinks, [_FakePlane.sink]);
      expect(sender.openedWith, encoder.started.single);
      expect(sender.credentials, _credentials);

      // A ready Sender is when the self-preview can be asked for.
      sender.ready();
      await Future<void>.delayed(Duration.zero);
      expect(ready, [_key]);

      // What the Sender asks of the encoder reaches the capture.
      sender.commands.add(const GoLiveBitrateCommand(2250000));
      sender.commands.add(const GoLiveKeyframeCommand());
      await Future<void>.delayed(Duration.zero);
      expect(encoder.bitrates, [2250000]);
      expect(encoder.keyframes, 1);

      // The stream's end takes its Sender with it.
      await controller.stop();
      expect(sender.closed, isTrue);
    },
  );

  test('a sender endpoint while nothing is shared is ignored', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final plane = _FakePlane();
    final endpoints = StreamController<DiscordSenderEndpoint>.broadcast();
    final controller = _controller(
      repository,
      plane: plane,
      endpoints: endpoints,
    );

    // The endpoint of a stream that already stopped: announcing on it would
    // bring the stream back as a ghost.
    endpoints.add((key: _key, credentials: _credentials));
    await Future<void>.delayed(Duration.zero);
    expect(plane.opened, isEmpty);

    // And one for a key that is not this stream's.
    await controller.start(channelId: 'voice-1', guildId: 'guild-1');
    endpoints.add((
      key: const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'me'),
      credentials: _credentials,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(plane.opened, isEmpty);
  });

  test('a replaced endpoint replaces the Sender once', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final plane = _FakePlane();
    final endpoints = StreamController<DiscordSenderEndpoint>.broadcast();
    final controller = _controller(
      repository,
      plane: plane,
      endpoints: endpoints,
    );
    final first = await _sending(controller, plane, endpoints);

    endpoints.add((key: _key, credentials: _credentials));
    await Future<void>.delayed(Duration.zero);

    expect(plane.opened, hasLength(2));
    expect(first.closed, isTrue);
    expect(plane.opened.last.closed, isFalse);
  });

  test('a reported settings change reaches the Sender', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final plane = _FakePlane();
    final endpoints = StreamController<DiscordSenderEndpoint>.broadcast();
    final capture = VideoCaptureHub(
      encoder: FakeVideoEncoder(),
      shareFrames: plane,
    );
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      capture: capture,
      media: plane,
      senderEndpoints: endpoints.stream,
    )..reconcile();
    addTearDown(controller.dispose);
    final sender = await _sending(controller, plane, endpoints);

    await capture.setQuality(
      const StreamQualitySettings(shareBitrate: 3000000),
    );
    await pumpEventQueue();
    expect(sender.reshaped.single.bitrate, 3000000);

    await capture.setQuality(
      const StreamQualitySettings(
        shareResolution: StreamResolution.p1080,
        shareFrameRate: 60,
      ),
    );
    await pumpEventQueue();
    expect(sender.reshaped.last.height, 1080);
    expect(sender.reshaped.last.framesPerSecond, 60);
    expect(controller.status, GoLiveStatus.creating);
    expect(controller.error, isNull);
  });

  test('a shape the encoder will not restart into is reported', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final encoder = FakeVideoEncoder();
    final plane = _FakePlane();
    final capture = VideoCaptureHub(encoder: encoder, shareFrames: plane);
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      capture: capture,
      media: plane,
    )..reconcile();
    addTearDown(controller.dispose);
    await controller.start(channelId: 'voice-1', guildId: 'guild-1');

    encoder.startFailure = StateError('no encoder');
    await capture.setQuality(
      const StreamQualitySettings(shareResolution: StreamResolution.p1080),
    );
    await pumpEventQueue();

    expect(controller.error, isA<StateError>());
    // The stream itself is still up; ending it is the user's call.
    expect(controller.isSharing, isTrue);
  });

  test('an encoder that fails leaves nothing announced', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    final controller = _controller(
      repository,
      encoder: FakeVideoEncoder()..startFailure = StateError('no encoder'),
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
    final encoder = FakeVideoEncoder(displays: 2);
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
    final encoder = FakeVideoEncoder(displays: 2);
    final controller = _controller(repository, encoder: encoder);

    await controller.start(sourceId: 'screen-1', channelId: 'voice-1');
    expect(
      await controller.start(sourceId: 'screen-2', channelId: 'voice-1'),
      isFalse,
    );

    // One capture, still the first one's.
    expect(encoder.started, hasLength(1));
  });

  test('a share while the camera holds the capture is refused', () async {
    final repository = _FakeRepository();
    addTearDown(repository.close);
    // One capture module, shared the way the app shares it: the camera and
    // the share are clients of the same one.
    final encoder = FakeVideoEncoder(cameras: const ['Webcam']);
    final capture = VideoCaptureHub(encoder: encoder);
    final camera = await capture.startCamera();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      capture: capture,
    )..reconcile();
    addTearDown(controller.dispose);

    expect(await controller.start(channelId: 'voice-1'), isFalse);

    // The capture module is the arbiter: with the camera on it, a share is
    // not started on the side and nothing is announced.
    expect(encoder.started, hasLength(1));
    expect(encoder.started.single.source, VideoCaptureSource.camera);
    expect(repository.started, isEmpty);
    expect(controller.status, GoLiveStatus.failure);
    expect(controller.error, isA<VideoEncoderException>());

    // And the camera itself is undisturbed.
    expect(capture.isCapturing, isTrue);
    expect(capture.settings!.source, VideoCaptureSource.camera);
    await camera.release();
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
    final encoder = FakeVideoEncoder(displays: 2);
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
      encoder: FakeVideoEncoder(displays: 2)..failStop = true,
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
      final encoder = FakeVideoEncoder(displays: 2);
      final controller = _controller(_FakeRepository(), encoder: encoder);

      expect(await controller.start(channelId: 'voice-1'), isTrue);

      // Nothing is named, and the capture module takes the primary display
      // for itself.
      expect(encoder.started, hasLength(1));
      expect(encoder.started.single.displayIndex, 0);
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
      final encoder = FakeVideoEncoder(displays: 2);
      final controller = _controller(_FakeRepository(), encoder: encoder);

      await controller.start(channelId: 'voice-1', sourceId: 'screen:2:0');

      // The picker names a screen by its index; the capture addresses
      // displays by the same index, and sharing the second monitor used to
      // encode the first.
      expect(encoder.started.single.displayIndex, 2);
    });
  });
}

/// Where each start delivers frames, and the Senders opened through it.
final class _FakePlane implements GoLiveMediaPlane {
  static const sink = 0xf00d;

  final List<_FakeSender> opened = [];

  @override
  Future<int?> get nativeFrameSink => Future.value(sink);

  @override
  Stream<EncodedVideoFrame> get relayedFrames =>
      const Stream<EncodedVideoFrame>.empty();

  @override
  GoLiveSender openSender({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
    required VideoEncoderSettings settings,
  }) {
    final sender = _FakeSender(credentials: credentials, openedWith: settings);
    opened.add(sender);
    return sender;
  }
}

/// A Sender that records what it was told and lets the test speak for the
/// far end: the bitrate and the keyframes it asks for, and its readiness.
final class _FakeSender implements GoLiveSender {
  _FakeSender({required this.credentials, required this.openedWith});

  final VoiceServerCredentials credentials;
  final VideoEncoderSettings openedWith;
  final List<VideoEncoderSettings> reshaped = [];
  final StreamController<GoLiveEncoderCommand> commands =
      StreamController.broadcast();
  final StreamController<GoLiveSenderStatus> _statuses =
      StreamController.broadcast();
  bool closed = false;

  @override
  GoLiveSenderStatus status = GoLiveSenderStatus.dialling;

  void ready() {
    status = GoLiveSenderStatus.ready;
    _statuses.add(status);
  }

  @override
  Stream<GoLiveSenderStatus> get statuses => _statuses.stream;

  @override
  Stream<GoLiveEncoderCommand> get encoderCommands => commands.stream;

  @override
  Stream<String> get paceLines => const Stream<String>.empty();

  @override
  void reshape(VideoEncoderSettings settings) => reshaped.add(settings);

  @override
  void sendOpusFrame(Uint8List opus) {}

  @override
  Future<void> close() async => closed = true;
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
