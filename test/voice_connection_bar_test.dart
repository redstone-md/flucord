import 'dart:async';

import 'package:flucord/src/app.dart';
import 'package:flucord/src/application/self_video_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/presentation/widgets/voice_connection_bar.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_video_encoder.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    VoiceController controller, {
    void Function(String channelId)? onOpenChannel,
    String? Function(String channelId)? nameFor,
    String? Function(String channelId)? serverFor,
    SelfVideoController? camera,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            // As wide as the channel sidebar it lives in.
            child: SizedBox(
              width: 236,
              child: VoiceConnectionBar(
                controller: controller,
                channelNameFor: nameFor ?? (_) => 'General',
                serverNameFor: serverFor ?? (_) => null,
                onOpenChannel: onOpenChannel,
                camera: camera,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('stays out of the way when nothing is connected', (tester) async {
    final controller = VoiceController(_FakeMedia());
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('voice-connection-bar')), findsNothing);
  });

  testWidgets('leaves the room from wherever the user navigated to', (
    tester,
  ) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    await pump(tester, controller);

    expect(find.byKey(const ValueKey('voice-connection-bar')), findsOne);
    expect(find.text('General'), findsOne);

    await tester.tap(find.byKey(const ValueKey('voice-bar-disconnect')));
    await tester.pumpAndSettle();

    expect(controller.isConnected, isFalse);
    expect(signaling.left, ['forge']);
  });

  testWidgets('walks back to the connected channel', (tester) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);
    final opened = <String>[];

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    await pump(tester, controller, onOpenChannel: opened.add);

    await tester.tap(find.byKey(const ValueKey('voice-bar-open')));
    await tester.pumpAndSettle();

    expect(opened, ['voice-1']);
  });

  testWidgets('says Voice connected in the success colour, above the room', (
    tester,
  ) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready),
    );
    await pump(tester, controller);

    final status = find.text('Voice connected');
    final style = tester.widget<Text>(status).style!;
    expect(style.color, _surfaces.success);
    expect(style.fontWeight, FontWeight.w500);
    final room = find.text('General');
    expect(tester.widget<Text>(room).style!.color, _surfaces.captionText);
    expect(
      tester.getRect(room).top,
      greaterThanOrEqualTo(tester.getRect(status).bottom),
    );
  });

  testWidgets('hang-up is a 32 px red button at the right', (tester) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    await pump(tester, controller);

    final panel = tester.getRect(
      find.byKey(const ValueKey('voice-connection-bar')),
    );
    final hangUp = find.byKey(const ValueKey('voice-bar-disconnect'));
    expect(tester.getSize(hangUp), const Size.square(32));
    expect(tester.getRect(hangUp).right, panel.right - 12);
    expect(_iconColour(tester, 'voice-bar-disconnect'), _surfaces.danger);
    final fill = _fillBehind(tester, 'voice-bar-disconnect');
    expect(fill.withValues(alpha: 1), _surfaces.danger);
    expect(fill.a, closeTo(0.12, 0.005));
  });

  testWidgets('camera, screen share and activities share the width evenly', (
    tester,
  ) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(),
      signalingServiceProvider: () => signaling,
    );
    final camera = SelfVideoController(
      capture: VideoCaptureHub(encoder: FakeVideoEncoder()),
      transportProvider: () => null,
      sinkProvider: () => null,
      isVoiceReady: () => true,
      announceSelfVideo: ({required enabled}) async => true,
    );
    addTearDown(controller.dispose);
    addTearDown(camera.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    await pump(tester, controller, camera: camera);

    final panel = tester.getRect(
      find.byKey(const ValueKey('voice-connection-bar')),
    );
    const keys = [
      'voice-bar-camera',
      'voice-bar-share',
      'voice-bar-activities',
    ];
    final buttons = [
      for (final key in keys) tester.getRect(find.byKey(ValueKey(key))),
    ];
    for (final button in buttons) {
      expect(button.height, 32);
      expect(button.width, closeTo(buttons.first.width, 0.5));
    }
    expect(buttons.first.left, panel.left + 12);
    expect(buttons.last.right, panel.right - 12);
    for (final key in keys) {
      expect(_fillBehind(tester, key).a, closeTo(0.05, 0.005));
    }
  });

  testWidgets('names the Room and its server where there is room to read it', (
    tester,
  ) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    await pump(
      tester,
      controller,
      onOpenChannel: (_) {},
      serverFor: (_) => 'Forge',
    );

    final names = find.text('General / Forge');
    expect(names, findsOneWidget);
    expect(tester.getSize(names).width, greaterThan(100));
  });

  testWidgets('from another server, a click returns to the Room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    Future<void> tap(String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    await tap('channel-forge-voice');
    await tap('voice-channel-join');
    // Reading the channel's chat, then walking off to another server.
    await tap('voice-surface-chat');
    await tap('space-night');
    expect(find.byKey(const ValueKey('channel-forge-voice')), findsNothing);
    expect(find.byKey(const ValueKey('voice-mute')), findsNothing);
    expect(find.text('workbench / The Forge'), findsOneWidget);

    await tap('voice-bar-open');

    expect(find.byKey(const ValueKey('channel-forge-voice')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);
  });

  testWidgets('a Room the workspace does not know has no way back', (
    tester,
  ) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    await pump(tester, controller, onOpenChannel: (_) {}, nameFor: (_) => null);

    // There is no channel to select. The bar still offers hang-up.
    expect(find.byKey(const ValueKey('voice-bar-open')), findsNothing);
    expect(find.byKey(const ValueKey('voice-bar-disconnect')), findsOne);
    expect(find.text('Voice channel'), findsOne);
  });

  testWidgets('reports a silent microphone', (tester) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(failMicrophone: true),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    await pump(tester, controller);

    expect(find.byKey(const ValueKey('voice-bar-warning')), findsOne);
  });
}

final _surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;

/// The colour the button with [key] draws its icon in.
Color? _iconColour(WidgetTester tester, String key) => tester
    .widget<FlucordIcon>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(FlucordIcon),
      ),
    )
    .color;

/// The fill painted behind the button with [key].
Color _fillBehind(WidgetTester tester, String key) => tester
    .widget<Material>(
      find
          .ancestor(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Material),
          )
          .first,
    )
    .color!;

final class _FakeSignaling implements VoiceSignalingService {
  @override
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.disconnected;

  @override
  VoiceTransportSession? currentSession;

  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final List<String> left = [];

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => const {};

  @override
  Stream<void> get seatedChanges => const Stream<void>.empty();

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) async {}

  @override
  Future<void> leaveVoiceChannel(String guildId) async => left.add(guildId);

  void emit(VoiceSignalingEvent event) => _events.add(event);

  Future<void> close() => _events.close();
}

final class _FakeMedia implements VoiceMediaService {
  _FakeMedia({this.failMicrophone = false});

  final bool failMicrophone;
  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphone.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [
    VoiceDevice(id: 'mic', label: 'Mic', kind: VoiceDeviceKind.audioInput),
  ];

  @override
  Future<void> startMicrophone(String? deviceId) async {
    if (failMicrophone) throw StateError('no capture device');
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> dispose() async {}
}
