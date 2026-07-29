import 'dart:async';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/presentation/widgets/voice_connection_bar.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    VoiceController controller, {
    void Function(String channelId)? onOpenChannel,
    String? Function(String channelId)? nameFor,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => VoiceConnectionBar(
              controller: controller,
              channelNameFor: nameFor ?? (_) => 'General',
              onOpenChannel: onOpenChannel,
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

    await tester.tap(find.byKey(const ValueKey('voice-bar-mute')));
    await tester.pumpAndSettle();
    expect(controller.isMuted, isTrue);

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

  testWidgets('a connection in another server has no way back', (tester) async {
    final signaling = _FakeSignaling();
    final controller = VoiceController(
      _FakeMedia(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'voice-1');
    await pump(tester, controller, onOpenChannel: (_) {}, nameFor: (_) => null);

    // The sidebar is showing a different space, so the channel is not one it
    // can select. The bar still offers mute and hang-up.
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

final class _FakeSignaling implements VoiceSignalingService {
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

  Future<void> close() => _events.close();
}

final class _FakeMedia implements VoiceMediaService {
  _FakeMedia({this.failMicrophone = false});

  final bool failMicrophone;
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
  Future<List<VoiceDevice>> enumerateDevices() async => const [
    VoiceDevice(id: 'mic', label: 'Mic', kind: VoiceDeviceKind.audioInput),
  ];

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async => const [];

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
  Future<void> startScreenShare(String sourceId) async {}

  @override
  Future<void> stopScreenShare() async {}

  @override
  Future<void> dispose() async {
    await _screenEnded.close();
    await _microphone.close();
  }
}
