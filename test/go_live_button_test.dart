import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/application/stream_quality_controller.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/stream_quality.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
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

  testWidgets('a transport that cannot stream refuses rather than vanishes', (
    tester,
  ) async {
    final controller = GoLiveController(
      repositoryProvider: () => null,
      capture: VideoCaptureHub(encoder: _FakeEncoder()),
    )..reconcile();
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('go-live-controls')), findsNothing);
    // This is the room's only share control now, and one that disappears
    // leaves somebody hunting for a button rather than reading why.
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('go-live-toggle')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the menu next to the button picks frame rate and size', (
    tester,
  ) async {
    final capture = VideoCaptureHub(encoder: _FakeEncoder());
    final controller = GoLiveController(
      repositoryProvider: _FakeRepository.new,
      capture: capture,
    )..reconcile();
    addTearDown(controller.dispose);
    final quality = StreamQualityController(
      _MemoryQualityRepository(),
      capture: capture,
    );
    addTearDown(quality.dispose);
    await quality.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: GoLiveButton(
            controller: controller,
            channelId: 'voice-1',
            quality: quality,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('go-live-quality')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('go-live-fps-60')));
    await tester.pumpAndSettle();

    expect(quality.shareFrameRate, 60);
    expect(capture.shareSettings.framesPerSecond, 60);

    await tester.tap(find.byKey(const ValueKey('go-live-quality')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('go-live-res-1080')));
    await tester.pumpAndSettle();

    expect(quality.shareResolution, StreamResolution.p1080);
    expect(capture.shareSettings.height, 1080);
  });

  testWidgets('shares what the picker chose, and nothing when dismissed', (
    tester,
  ) async {
    final encoder = _FakeEncoder();
    final controller = GoLiveController(
      repositoryProvider: _FakeRepository.new,
      capture: VideoCaptureHub(encoder: encoder),
    )..reconcile();
    addTearDown(controller.dispose);
    String? answer = 'screen:1:0';

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => GoLiveButton(
              controller: controller,
              channelId: 'voice-1',
              guildId: 'guild-1',
              pickSource: () async => answer,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    // Handed to the capture module, which is the only thing that captures: a
    // second duplication of the same display is refused by Windows.
    expect(encoder.settings?.displayIndex, 1);

    await controller.stop();
    await tester.pumpAndSettle();
    answer = null;

    encoder.settings = null;
    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    // Dismissed. Sharing the primary screen because somebody closed a picker
    // would put the wrong thing in the channel, which is worse than nothing.
    expect(encoder.settings, isNull);
  });

  testWidgets('starts and stops a stream, driving the encoder with it', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final encoder = _FakeEncoder();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      capture: VideoCaptureHub(encoder: encoder),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    // The capture module captures the primary display for itself.
    expect(encoder.started, 1);
    expect(repository.started, ['voice-1']);

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    expect(repository.ended, [_key]);
    expect(encoder.stopped, greaterThan(0));
  });

  testWidgets('a build with no encoder cannot start one', (tester) async {
    final repository = _FakeRepository();
    final controller = GoLiveController(
      repositoryProvider: () => repository,
      capture: VideoCaptureHub(encoder: _FakeEncoder(supported: false)),
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
      capture: VideoCaptureHub(encoder: _FakeEncoder()),
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

    // The unpause that follows the create comes first: Discord's own clients
    // send one, and a stream that never does has its RTC session refused.
    expect(repository.pauses, [false, true]);
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
      capture: VideoCaptureHub(encoder: _FakeEncoder()),
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
      capture: VideoCaptureHub(encoder: encoder),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);
    addTearDown(encoder.close);

    var packets = 0;
    controller.bindTransport(
      ssrc: 7,
      rtxSsrc: 9,
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
      capture: VideoCaptureHub(encoder: _FakeEncoder(supported: false)),
    )..reconcile();
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    controller.bindTransport(ssrc: 7, rtxSsrc: 9, sink: (frame) => 0);

    expect(controller.sentPackets, 0);
    expect(controller.canEncode, isFalse);
  });
}

final class _MemoryQualityRepository implements StreamQualityRepository {
  StreamQualitySettings _settings = const StreamQualitySettings();

  @override
  Future<StreamQualitySettings> load() async => _settings;

  @override
  Future<void> save(StreamQualitySettings settings) async {
    _settings = settings;
  }
}

final class _FakeEncoder implements VideoEncoderService {
  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  _FakeEncoder({this.supported = true});

  final bool supported;
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();
  int started = 0;
  VideoEncoderSettings? settings;
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
  Future<void> start(VideoEncoderSettings requested) async {
    started++;
    settings = requested;
  }

  @override
  Future<void> requestKeyframe() async {}

  @override
  Future<void> setPaused({required bool paused}) async => pauses.add(paused);

  @override
  Future<void> stop() async => stopped++;
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
