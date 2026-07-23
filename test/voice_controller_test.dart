import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_media.dart';

void main() {
  test('controls media devices, microphone, and screen lifecycle', () async {
    final media = _FakeVoiceMediaService();
    final controller = VoiceController(media);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.state, VoiceState.ready);
    expect(controller.selectedInputId, 'mic-1');
    expect(controller.selectedOutputId, 'speaker-1');

    await controller.connect(guildId: 'forge', channelId: 'forge-voice');
    expect(controller.isConnected, isTrue);
    expect(media.startedInputs, ['mic-1']);
    expect(media.microphoneEnabled, isTrue);

    await controller.toggleMute();
    expect(controller.isMuted, isTrue);
    expect(media.microphoneEnabled, isFalse);

    await controller.selectInput('mic-2');
    await controller.selectOutput('speaker-2');
    expect(media.startedInputs, ['mic-1', 'mic-2']);
    expect(media.selectedOutput, 'speaker-2');
    expect(media.microphoneEnabled, isFalse);

    await controller.loadCaptureSources();
    expect(controller.captureSources.single.id, 'screen-1');
    await controller.shareScreen('screen-1');
    expect(controller.isScreenSharing, isTrue);
    expect(media.sharedSource, 'screen-1');

    media.endScreenShare();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isScreenSharing, isFalse);

    await controller.disconnect();
    expect(controller.isConnected, isFalse);
    expect(media.microphoneStopped, isTrue);
    expect(media.screenStopped, isTrue);
  });

  test('tracks Discord voice signaling without claiming RTP audio', () async {
    final media = _FakeVoiceMediaService();
    final signaling = _FakeVoiceSignalingService();
    final controller = VoiceController(
      media,
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
    expect(signaling.joins, [('guild-1', 'voice-1', false)]);
    expect(controller.connectionStatus, VoiceConnectionStatus.joining);

    signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.negotiating),
    );
    signaling.emit(
      const VoiceTransportReadyEvent(
        VoiceTransportSession(
          guildId: 'guild-1',
          ssrc: 42,
          address: '203.0.113.7',
          port: 50000,
          mode: 'aead_xchacha20_poly1305_rtpsize',
          secretKey: [1, 2, 3],
          daveProtocolVersion: 1,
        ),
      ),
    );
    signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.isTransportReady, isTrue);
    expect(controller.transportSession?.ssrc, 42);

    await controller.toggleMute();
    expect(signaling.joins.last, ('guild-1', 'voice-1', true));

    await controller.disconnect();
    expect(signaling.leftGuilds, ['guild-1']);
    expect(controller.isConnected, isFalse);
  });

  test('rebinds an active room when the repository changes', () async {
    final first = _FakeVoiceSignalingService();
    final second = _FakeVoiceSignalingService();
    VoiceSignalingService active = first;
    final controller = VoiceController(
      _FakeVoiceMediaService(),
      signalingServiceProvider: () => active,
    );
    addTearDown(controller.dispose);
    addTearDown(first.close);
    addTearDown(second.close);

    await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
    active = second;
    await controller.refreshSignalingService();

    expect(first.joins, [('guild-1', 'voice-1', false)]);
    expect(second.joins, [('guild-1', 'voice-1', false)]);
    expect(controller.hasDiscordSignaling, isTrue);
  });
}

final class _FakeVoiceSignalingService implements VoiceSignalingService {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final List<(String, String, bool)> joins = [];
  final List<String> leftGuilds = [];

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  void emit(VoiceSignalingEvent event) => _events.add(event);

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
  }) async {
    joins.add((guildId, channelId, selfMute));
  }

  @override
  Future<void> leaveVoiceChannel(String guildId) async {
    leftGuilds.add(guildId);
  }

  Future<void> close() => _events.close();
}

final class _FakeVoiceMediaService implements VoiceMediaService {
  final StreamController<void> _screenEnded = StreamController.broadcast();
  final List<String?> startedInputs = [];
  bool microphoneEnabled = true;
  bool microphoneStopped = false;
  bool screenStopped = false;
  String? selectedOutput;
  String? sharedSource;

  void endScreenShare() => _screenEnded.add(null);

  @override
  Object? get previewRenderer => null;

  @override
  Stream<void> get screenShareEnded => _screenEnded.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [
    VoiceDevice(
      id: 'mic-1',
      label: 'Primary microphone',
      kind: VoiceDeviceKind.audioInput,
    ),
    VoiceDevice(
      id: 'mic-2',
      label: 'Backup microphone',
      kind: VoiceDeviceKind.audioInput,
    ),
    VoiceDevice(
      id: 'speaker-1',
      label: 'Primary speakers',
      kind: VoiceDeviceKind.audioOutput,
    ),
    VoiceDevice(
      id: 'speaker-2',
      label: 'Headset',
      kind: VoiceDeviceKind.audioOutput,
    ),
  ];

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async => [
    VoiceCaptureSource(
      id: 'screen-1',
      name: 'Entire screen',
      kind: VoiceCaptureKind.screen,
      thumbnail: Uint8List(0),
    ),
  ];

  @override
  Future<void> selectAudioOutput(String deviceId) async {
    selectedOutput = deviceId;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    microphoneEnabled = enabled;
  }

  @override
  Future<void> startMicrophone(String? deviceId) async {
    startedInputs.add(deviceId);
  }

  @override
  Future<void> startScreenShare(String sourceId) async {
    sharedSource = sourceId;
  }

  @override
  Future<void> stopMicrophone() async {
    microphoneStopped = true;
  }

  @override
  Future<void> stopScreenShare() async {
    screenStopped = true;
  }

  @override
  Future<void> dispose() async {
    await _screenEnded.close();
  }
}
