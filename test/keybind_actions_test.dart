import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/keybind_actions.dart';
import 'package:flucord/src/application/self_video_controller.dart';
import 'package:flucord/src/application/streamer_mode_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/application/voice_overlay_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/video/clip_recorder.dart';
import 'package:flucord/src/data/video/screenshot_service.dart';
import 'package:flucord/src/domain/keybind.dart';
import 'package:flucord/src/domain/streamer_mode.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/platform/voice_overlay.dart';

void main() {
  late VoiceController voice;
  late StreamerModeController streamerMode;
  late VoiceOverlayController overlay;
  late KeybindActions actions;

  setUp(() {
    voice = VoiceController(_FakeVoiceMediaService());
    streamerMode = StreamerModeController(_NoSettings());
    overlay = VoiceOverlayController(
      overlay: _CountingVoiceOverlay(),
      roster: () => const [],
      isHiddenByStreamerMode: () => false,
    );
    actions = KeybindActions(
      voice: voice,
      selfVideo: SelfVideoController(
        capture: VideoCaptureHub(encoder: _FakeEncoderService()),
        transportProvider: () => null,
        sinkProvider: () => null,
        announceSelfVideo: ({required bool enabled}) async => true,
      ),
      workspace: WorkspaceController(),
      streamerMode: streamerMode,
      overlay: overlay,
      screenshot: const UnavailableScreenshotService(),
      clip: const UnavailableClipRecorder(),
      messenger: GlobalKey<ScaffoldMessengerState>(),
    );
  });

  /// Mute and deafen are room state: a controller with no connection rightly
  /// refuses to touch them, so these tests stand in a connected room first.
  Future<void> connectRoom() async {
    await voice.initialize();
    await voice.connect(guildId: 'forge', channelId: 'forge-voice');
  }

  test('push to talk unmutes on press and mutes on release', () async {
    await connectRoom();

    actions(KeybindAction.pushToTalk, pressed: true);
    await Future<void>.delayed(Duration.zero);
    expect(voice.isMuted, isFalse);

    actions(KeybindAction.pushToTalk, pressed: false);
    await Future<void>.delayed(Duration.zero);
    expect(voice.isMuted, isTrue);
  });

  test('push to mute is the opposite direction of the same flag', () async {
    await connectRoom();

    actions(KeybindAction.pushToMute, pressed: true);
    await Future<void>.delayed(Duration.zero);
    expect(voice.isMuted, isTrue);

    actions(KeybindAction.pushToMute, pressed: false);
    await Future<void>.delayed(Duration.zero);
    expect(voice.isMuted, isFalse);
  });

  test('toggle actions fire on press only, and releases do nothing', () async {
    await connectRoom();

    actions(KeybindAction.toggleMute, pressed: false);
    await Future<void>.delayed(Duration.zero);
    expect(voice.isMuted, isFalse, reason: 'a release is not a toggle');

    actions(KeybindAction.toggleDeafen, pressed: true);
    await Future<void>.delayed(Duration.zero);
    expect(voice.isDeafened, isTrue);

    actions(KeybindAction.toggleDeafen, pressed: false);
    await Future<void>.delayed(Duration.zero);
    expect(voice.isDeafened, isTrue, reason: 'still only presses toggle');
  });

  test('the overlay toggle reaches the overlay controller', () async {
    actions(KeybindAction.toggleOverlay, pressed: true);
    await Future<void>.delayed(Duration.zero);
    expect(overlay.isWanted, isTrue);

    actions(KeybindAction.toggleOverlay, pressed: true);
    await Future<void>.delayed(Duration.zero);
    expect(overlay.isWanted, isFalse);
  });
}

class _FakeVoiceMediaService implements VoiceMediaService {
  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphone.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [];

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> dispose() async {}
}

class _CountingVoiceOverlay implements VoiceOverlay {
  int shows = 0;
  int hides = 0;

  @override
  bool get isSupported => true;

  @override
  bool get isVisible => shows > hides;

  @override
  Future<bool> show(List<OverlaySpeaker> speakers) async {
    shows++;
    return true;
  }

  @override
  void hide() => hides++;

  @override
  void close() {}
}

class _FakeEncoderService implements VideoEncoderService {
  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  @override
  bool get isSupported => false;

  @override
  List<String> get cameraNames => const [];

  @override
  int get displayCount => 1;

  @override
  Stream<EncodedVideoFrame> get frames => const Stream.empty();

  @override
  Future<void> start(VideoEncoderSettings settings) async {}

  @override
  Future<void> requestKeyframe() async {}

  @override
  Future<void> setPaused({required bool paused}) async {}

  @override
  Future<void> stop() async {}
}

class _NoSettings implements StreamerModeRepository {
  @override
  Future<StreamerModeSettings> load() async => const StreamerModeSettings();

  @override
  Future<void> save(StreamerModeSettings settings) async {}
}
