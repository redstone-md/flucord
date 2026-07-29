import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/presentation/widgets/go_live_button.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

void main() {
  Future<void> pump(WidgetTester tester, GoLiveController controller) =>
      tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => GoLiveButton(
                controller: controller,
                channelId: 'voice-1',
                guildId: 'guild-1',
              ),
            ),
          ),
        ),
      );

  testWidgets('a transport that cannot stream shows nothing', (tester) async {
    final controller = GoLiveController(
      repositoryProvider: () => null,
      mediaService: _FakeMedia(),
      encoder: _FakeEncoder(),
    )..reconcile();
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('go-live-controls')), findsNothing);
  });

  testWidgets('starts and stops a stream, driving the encoder with it', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final encoder = _FakeEncoder();
    final media = _FakeMedia();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: media,
      encoder: encoder,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    expect(media.shared, ['0']);
    expect(encoder.started, 1);
    expect(repository.started, ['voice-1']);

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    expect(repository.ended, [_key]);
    expect(encoder.stopped, greaterThan(0));
    expect(media.stopped, greaterThan(0));
  });

  testWidgets('a build with no encoder cannot start one', (tester) async {
    final repository = _FakeRepository();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
      encoder: _FakeEncoder(supported: false),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);

    // The control stays, disabled, rather than vanishing: watching still works
    // on such a build and the difference is worth showing.
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('go-live-toggle')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('shows who is watching and pauses', (tester) async {
    final repository = _FakeRepository();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
      encoder: _FakeEncoder(),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();
    repository
      ..assign(const GoLiveServer(key: _key, endpoint: 'e', token: 't'))
      ..announce(const GoLiveStream(key: _key, viewerIds: ['a', 'b']));
    await tester.pumpAndSettle();

    expect(find.text('2 watching'), findsOne);

    await tester.tap(find.byKey(const ValueKey('go-live-pause')));
    await tester.pumpAndSettle();

    expect(repository.pauses, [true]);
    expect(controller.status, GoLiveStatus.paused);

    // A live stream keeps a ping timer running, and the binding refuses to
    // end a test with one pending.
    await controller.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('a refused stream is reported', (tester) async {
    final repository = _FakeRepository(failStart: true);
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
      encoder: _FakeEncoder(),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('go-live-error')), findsOne);
  });

  test('binding a transport sends what the encoder produces', () async {
    final repository = _FakeRepository();
    final encoder = _FakeEncoder();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
      encoder: encoder,
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);
    addTearDown(encoder.close);

    var packets = 0;
    controller.bindTransport(
      ssrc: 7,
      sink: (frame) {
        packets++;
        return frame.payload.length;
      },
    );
    encoder.emit(
      EncodedVideoFrame(
        bytes: Uint8List.fromList([0, 0, 0, 1, 0x65, 1, 2, 3]),
        timestamp: Duration.zero,
        isKeyframe: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(packets, 1);
    expect(controller.sentPackets, 1);
    expect(controller.transportError, isNull);
    expect(controller.canEncode, isTrue);
  });

  test('a build without an encoder binds nothing', () async {
    final repository = _FakeRepository();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      mediaService: _FakeMedia(),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    controller.bindTransport(ssrc: 7, sink: (frame) => 0);

    expect(controller.sentPackets, 0);
    expect(controller.canEncode, isFalse);
  });
}

final class _FakeEncoder implements VideoEncoderService {
  _FakeEncoder({this.supported = true});

  final bool supported;
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();
  int started = 0;
  int stopped = 0;
  final List<bool> pauses = [];
  List<String> cameras = const [];

  @override
  List<String> get cameraNames => cameras;

  void emit(EncodedVideoFrame frame) => _frames.add(frame);

  Future<void> close() => _frames.close();

  @override
  bool get isSupported => supported;

  @override
  int get displayCount => supported ? 1 : 0;

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start(VideoEncoderSettings settings) async => started++;

  @override
  Future<void> requestKeyframe() async {}

  @override
  Future<void> setPaused({required bool paused}) async => pauses.add(paused);

  @override
  Future<void> stop() async => stopped++;
}

final class _FakeMedia implements VoiceMediaService {
  final StreamController<void> _screenEnded = StreamController.broadcast();
  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();
  final List<String> shared = [];
  int stopped = 0;

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

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async => const [];

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> startScreenShare(String sourceId) async => shared.add(sourceId);

  @override
  Future<void> stopScreenShare() async => stopped++;

  @override
  Future<void> dispose() async {
    await _screenEnded.close();
    await _microphone.close();
  }
}

final class _FakeRepository implements GoLiveRepository {
  _FakeRepository({this.failStart = false});

  final bool failStart;
  final StreamController<GoLiveStream> _updates = StreamController.broadcast();
  final StreamController<GoLiveServer> _servers = StreamController.broadcast();
  final List<String> started = [];
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
    return GoLiveStreamKey.guild(
      guildId: guildId ?? 'guild-1',
      channelId: channelId,
      userId: 'me',
    );
  }

  @override
  Future<void> watchStream(GoLiveStreamKey key) async {}

  @override
  Future<void> pingStream(GoLiveStreamKey key) async {}

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async =>
      pauses.add(paused);

  @override
  Future<void> endStream(GoLiveStreamKey key) async => ended.add(key);

  Future<void> close() async {
    await _updates.close();
    await _servers.close();
  }
}
