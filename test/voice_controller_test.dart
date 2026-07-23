import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_controller.dart';
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

    await controller.connect('forge-voice');
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
