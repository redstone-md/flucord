import 'dart:async';

import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

void main() {
  test('a transport that cannot stream offers nothing', () async {
    final media = _FakeMedia();
    final controller = GoLiveController(
      repositoryProvider: () => null,
      mediaService: media,
    )..reconcile();
    addTearDown(controller.dispose);

    expect(controller.isSupported, isFalse);
    expect(
      await controller.start(sourceId: 'screen-1', channelId: 'voice-1'),
      isFalse,
    );
    expect(await controller.watch(_key), isFalse);
    expect(media.shared, isEmpty);
  });

  test('captures before announcing, and pings while live', () async {
    final repository = _FakeRepository();
    final media = _FakeMedia();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: media,
      pingInterval: const Duration(milliseconds: 10),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    expect(
      await controller.start(
        sourceId: 'screen-1',
        channelId: 'voice-1',
        guildId: 'guild-1',
      ),
      isTrue,
    );

    // A stream announced with nothing behind it shows viewers a black
    // rectangle, so the capture goes first.
    expect(media.shared, ['screen-1']);
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
    expect(media.stopped, 1);
    expect(repository.ended, [_key]);
    expect(controller.status, GoLiveStatus.idle);
    expect(controller.streamKey, isNull);
    expect(controller.viewerIds, isEmpty);

    final pings = repository.pings.length;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // The ping stops with the stream.
    expect(repository.pings.length, pings);
  });

  test('a capture that fails leaves nothing announced', () async {
    final repository = _FakeRepository();
    final media = _FakeMedia(failShare: true);
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: media,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    expect(
      await controller.start(sourceId: 'screen-1', channelId: 'voice-1'),
      isFalse,
    );

    expect(controller.status, GoLiveStatus.failure);
    expect(controller.error, isNotNull);
    expect(repository.started, isEmpty);
    expect(media.stopped, 1);
  });

  test('a refused stream stops the capture behind it', () async {
    final repository = _FakeRepository(failStart: true);
    final media = _FakeMedia();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: media,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    expect(
      await controller.start(sourceId: 'screen-1', channelId: 'voice-1'),
      isFalse,
    );

    expect(controller.status, GoLiveStatus.failure);
    expect(media.stopped, 1);
  });

  test('a second start while one is running is refused', () async {
    final repository = _FakeRepository();
    final media = _FakeMedia();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: media,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await controller.start(sourceId: 'screen-1', channelId: 'voice-1');
    expect(
      await controller.start(sourceId: 'screen-2', channelId: 'voice-1'),
      isFalse,
    );

    expect(media.shared, ['screen-1']);
  });

  test('pausing and resuming report themselves', () async {
    final repository = _FakeRepository();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

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
    expect(repository.pauses, [true, false]);
  });

  test('a pause somebody else applied is followed', () async {
    final repository = _FakeRepository();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);
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
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);
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
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);
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
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    const other = GoLiveStreamKey.call(channelId: 'dm-1', userId: 'them');
    expect(await controller.watch(other), isTrue);
    expect(repository.watched, [other]);

    repository.failWatch = true;
    expect(await controller.watch(other), isFalse);
    expect(controller.error, isNotNull);
  });

  test('stopping what was never started tears nothing down', () async {
    final repository = _FakeRepository();
    final media = _FakeMedia();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: media,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await controller.stop();

    expect(repository.ended, isEmpty);
    expect(controller.status, GoLiveStatus.idle);
    // The capture is stopped regardless: it may be running without a stream
    // if the announce failed.
    expect(media.stopped, 1);
  });

  test('an end Discord refuses still releases the capture', () async {
    final repository = _FakeRepository(failEnd: true);
    final media = _FakeMedia();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: media,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);
    await controller.start(
      sourceId: 'screen-1',
      channelId: 'voice-1',
      guildId: 'guild-1',
    );

    await controller.stop();

    expect(controller.error, isNotNull);
    expect(media.stopped, 1);
    expect(controller.streamKey, isNull);
  });

  test('a capture that will not stop does not mask the reason', () async {
    final repository = _FakeRepository();
    final media = _FakeMedia(failStop: true);
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: media,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);
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
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
    )..reconcile();
    addTearDown(controller.dispose);

    repository = _FakeRepository();
    addTearDown(() => repository.close());
    controller
      ..reconcile()
      ..reconcile();

    expect(controller.isSupported, isTrue);
  });
  group('sharing without picking a source', () {
    test('shares the screen the platform reports, not an invented id', () async {
      final media = _FakeMedia();
      final controller = GoLiveController(
        repositoryProvider: () => _FakeRepository(),
        mediaService: media,
      )..reconcile();
      addTearDown(controller.dispose);

      expect(await controller.start(channelId: 'voice-1'), isTrue);

      // Nothing is named. A capture source id is a handle into a list that
      // changes when a display sleeps or is unplugged: the invented "0" failed
      // with "source not found", and a real id read moments earlier failed
      // with "that display is no longer attached".
      expect(media.shared, ['<primary screen>']);
    });

    test('a machine with no display to capture reports what it was told',
        () async {
      final media = _FakeMedia(failShare: true);
      final controller = GoLiveController(
        repositoryProvider: () => _FakeRepository(),
        mediaService: media,
      )..reconcile();
      addTearDown(controller.dispose);

      expect(await controller.start(channelId: 'voice-1'), isFalse);

      expect(controller.status, GoLiveStatus.failure);
      expect(controller.error.toString(), contains('no display'));
    });
  });
}

final class _FakeMedia implements VoiceMediaService {
  _FakeMedia({this.failShare = false, this.failStop = false});

  final bool failShare;
  final bool failStop;
  final List<String> shared = [];
  int stopped = 0;

  final StreamController<void> _screenEnded = StreamController.broadcast();
  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();

  @override
  Object? get previewRenderer => null;

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphone.stream;

  @override
  Stream<void> get screenShareEnded => _screenEnded.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [];

  List<VoiceCaptureSource> sources = const [
    VoiceCaptureSource(
      id: 'window:7',
      name: 'A window',
      kind: VoiceCaptureKind.window,
    ),
    VoiceCaptureSource(
      id: 'screen:0:0',
      name: 'Primary screen',
      kind: VoiceCaptureKind.screen,
    ),
  ];

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async => sources;

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> startScreenShare(String? sourceId) async {
    if (failShare) throw StateError('no display');
    shared.add(sourceId ?? '<primary screen>');
  }

  @override
  Future<void> stopScreenShare() async {
    stopped++;
    if (failStop) throw StateError('already gone');
  }

  @override
  Future<void> dispose() async {
    await _screenEnded.close();
    await _microphone.close();
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
