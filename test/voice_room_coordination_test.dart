import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/application/remote_camera_controller.dart';
import 'package:flucord/src/application/streamer_mode_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/application/voice_overlay_controller.dart';
import 'package:flucord/src/application/voice_room_coordination.dart';
import 'package:flucord/src/data/noop_voice_media_service.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/streamer_mode.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/platform/voice_overlay.dart';

import 'support/fake_video_encoder.dart';

void main() {
  test('remote cameras follow the room connection', () async {
    final signaling = _FakeVoiceSignalingService();
    final voice = VoiceController(
      const NoopVoiceMediaService(),
      signalingServiceProvider: () => signaling,
    );
    final cameras = RemoteCameraController(
      packetsProvider: () => const Stream.empty(),
      decoderFactory: () => throw StateError('no camera packets in this test'),
    );
    final room = _buildRoom(voice: voice, remoteCameras: cameras);

    await voice.refreshSignalingService();
    expect(cameras.isListening, isFalse);

    signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cameras.isListening, isTrue);

    signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.disconnected),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cameras.isListening, isFalse);

    room.dispose();
    signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cameras.isListening, isFalse, reason: 'rules die with the room');
  });

  test('the overlay redraws whenever the room changes', () async {
    final signaling = _FakeVoiceSignalingService();
    final voice = VoiceController(
      const NoopVoiceMediaService(),
      signalingServiceProvider: () => signaling,
    );
    final overlay = _CountingVoiceOverlay();
    final overlayController = VoiceOverlayController(
      overlay: overlay,
      roster: () => const [],
      isHiddenByStreamerMode: () => false,
    );
    final room = _buildRoom(voice: voice, overlayController: overlayController);

    await voice.refreshSignalingService();
    await overlayController.toggle();
    expect(overlay.shows, 1);

    signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.reconnecting),
    );
    await Future<void>.delayed(Duration.zero);
    expect(overlay.shows, 2, reason: 'a roster change redraws the overlay');

    room.dispose();
  });

  test(
    "streamer mode's automatic switch follows this client's share",
    () async {
      final repository = _FakeGoLiveRepository();
      final goLive = GoLiveController(
        repositoryProvider: () => repository,
        capture: VideoCaptureHub(encoder: FakeVideoEncoder(supported: false)),
      );
      final settings = _MemoryStreamerModeSettings();
      final streamerMode = StreamerModeController(settings);
      await streamerMode.load();
      expect(streamerMode.isEnabled, isFalse);

      final room = _buildRoom(streamerMode: streamerMode, goLive: goLive);
      const key = GoLiveStreamKey.call(channelId: 'c', userId: 'me');
      await goLive.start(channelId: 'c');

      repository.announce(const GoLiveStream(key: key));
      await Future<void>.delayed(Duration.zero);
      repository.assign(
        const GoLiveServer(key: key, endpoint: 'e', token: 't'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(goLive.isStreaming, isTrue);
      expect(streamerMode.isEnabled, isTrue);

      room.dispose();
    },
  );
}

/// Wires one [VoiceRoomCoordination] with whatever the test cares about;
/// the rest get inert stand-ins, the same shape the real graph gives them.
VoiceRoomCoordination _buildRoom({
  VoiceController? voice,
  RemoteCameraController? remoteCameras,
  VoiceOverlayController? overlayController,
  StreamerModeController? streamerMode,
  GoLiveController? goLive,
}) {
  final resolvedVoice =
      voice ??
      VoiceController(
        const NoopVoiceMediaService(),
        signalingServiceProvider: () => null,
      );
  final room = VoiceRoomCoordination(
    voice: resolvedVoice,
    remoteCameras:
        remoteCameras ??
        RemoteCameraController(
          packetsProvider: () => const Stream.empty(),
          decoderFactory: () => throw StateError('unused'),
        ),
    overlay:
        overlayController ??
        VoiceOverlayController(
          overlay: _CountingVoiceOverlay(),
          roster: () => const [],
          isHiddenByStreamerMode: () => false,
        ),
    streamerMode: streamerMode ?? StreamerModeController(_NoSettings()),
    goLive:
        goLive ??
        GoLiveController(
          repositoryProvider: () => null,
          capture: VideoCaptureHub(encoder: FakeVideoEncoder(supported: false)),
        ),
  );
  return room;
}

class _FakeVoiceSignalingService implements VoiceSignalingService {
  @override
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.disconnected;

  @override
  VoiceTransportSession? currentSession;

  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  void emit(VoiceSignalingEvent event) => _events.add(event);

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => const {};

  @override
  Stream<void> get seatedChanges => const Stream.empty();

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) async {}

  @override
  Future<void> leaveVoiceChannel(String guildId) async {}
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

class _FakeGoLiveRepository implements GoLiveRepository {
  final StreamController<GoLiveStream> _updates = StreamController.broadcast();

  void announce(GoLiveStream stream) => _updates.add(stream);

  @override
  Map<String, GoLiveStream> get streams => const {};

  @override
  Stream<GoLiveStream> get updates => _updates.stream;

  final StreamController<GoLiveServer> _servers = StreamController.broadcast();

  void assign(GoLiveServer server) => _servers.add(server);

  @override
  Stream<GoLiveServer> get servers => _servers.stream;

  @override
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) async => GoLiveStreamKey.call(channelId: channelId, userId: 'me');

  @override
  Future<void> watchStream(GoLiveStreamKey key) async {}

  @override
  Future<void> pingStream(GoLiveStreamKey key) async {}

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async {}

  @override
  Future<void> endStream(GoLiveStreamKey key) async {}
}

class _MemoryStreamerModeSettings implements StreamerModeRepository {
  StreamerModeSettings _settings = const StreamerModeSettings();

  @override
  Future<StreamerModeSettings> load() async => _settings;

  @override
  Future<void> save(StreamerModeSettings settings) async {
    _settings = settings;
  }
}

class _NoSettings implements StreamerModeRepository {
  @override
  Future<StreamerModeSettings> load() async => const StreamerModeSettings();

  @override
  Future<void> save(StreamerModeSettings settings) async {}
}
