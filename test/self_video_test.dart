import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flucord/src/application/self_video_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_protocol.dart';
import 'package:flucord/src/data/noop_voice_media_service.dart';
import 'package:flucord/src/data/video/native_camera_names.dart';
import 'package:flucord/src/data/video/native_video_encoder_service.dart';
import 'package:flucord/src/domain/stream_quality.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/voice_connection_bar.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what opcode 12 says', () {
    test('the SSRCs are derived from the audio one, not invented', () {
      final protocol = DiscordVoiceGatewayProtocol(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
      );

      final frame = protocol.video(
        audioSsrc: 40,
        enabled: true,
        settings: _cameraProfile,
      );
      final body = frame['d']! as Map<String, Object?>;
      final stream = (body['streams']! as List).single as Map<String, Object?>;

      expect(frame['op'], 12);
      expect(body['audio_ssrc'], 40);
      // Video is one above the audio SSRC and the retransmission stream one
      // above that, which is what the desktop client derives.
      expect(body['video_ssrc'], 41);
      expect(body['rtx_ssrc'], 42);
      expect(DiscordVoiceGatewayProtocol.videoSsrcFor(40), 41);
      expect(stream['type'], 'video');
      expect(stream['rid'], '100');
      expect(stream['ssrc'], 41);
      expect(stream['active'], isTrue);
      expect(stream['quality'], 100);
      expect(stream['max_resolution'], {
        'type': 'fixed',
        'width': 1280,
        'height': 720,
      });
    });

    test('turning the camera off keeps the stream declared and inactive', () {
      final protocol = DiscordVoiceGatewayProtocol(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
      );

      final body =
          protocol.video(
                audioSsrc: 7,
                enabled: false,
                settings: _cameraProfile,
              )['d']!
              as Map<String, Object?>;
      final stream = (body['streams']! as List).single as Map<String, Object?>;

      expect(stream['active'], isFalse);
      // The SSRCs stay: the renderer marks the stream inactive rather than
      // withdrawing the numbers it announced.
      expect(body['video_ssrc'], 8);
    });

    test('the encoder settings reach the announcement', () {
      final protocol = DiscordVoiceGatewayProtocol(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
      );

      final body =
          protocol.video(
                audioSsrc: 1,
                enabled: true,
                settings: const VideoEncoderSettings(
                  bitrate: 500000,
                  width: 640,
                  height: 480,
                  framesPerSecond: 15,
                ),
              )['d']!
              as Map<String, Object?>;
      final stream = (body['streams']! as List).single as Map<String, Object?>;

      expect(stream['max_framerate'], 15);
      expect(stream['max_bitrate'], 500000);
      expect(stream['max_resolution'], {
        'type': 'fixed',
        'width': 640,
        'height': 480,
      });
    });
  });

  group('a build without the native module', () {
    // The DLL is not on a test host, so this is the shape every non-Windows
    // build and every developer machine without it actually runs in — and the
    // one where a missing null check would take the whole client down.
    test('reports itself unavailable rather than failing to construct', () {
      final service = NativeVideoEncoderService();
      addTearDown(service.close);

      expect(service.isSupported, isFalse);
      expect(service.displayCount, 0);
      expect(service.cameraNames, isEmpty);
    });

    test('refuses to start, and the rest is quietly a no-op', () async {
      final service = NativeVideoEncoderService();
      addTearDown(service.close);

      await expectLater(
        service.start(_cameraProfile),
        throwsA(
          isA<VideoEncoderException>().having(
            (error) => error.failure,
            'failure',
            VideoEncoderFailure.unsupported,
          ),
        ),
      );

      // Nothing is open, so none of these have anything to act on.
      await service.requestKeyframe();
      await service.setPaused(paused: true);
      await service.stop();
    });
  });

  group('reading the camera names', () {
    test('a name comes back through the two-call protocol', () {
      final reader = _StubNames(const ['Integrated Webcam', 'Studio Cam']);

      expect(NativeCameraNames.read(count: 2, name: reader.call), [
        'Integrated Webcam',
        'Studio Cam',
      ]);
      // Sized first, written second: the length call must not write anything.
      expect(reader.sizings, 2);
    });

    test('a camera the platform will not name keeps its place', () {
      // Empty, refused, and a length of only the terminator: all three are a
      // camera that still has to be selectable by position.
      final reader = _StubNames(const ['', 'Studio Cam'], refuse: {1});

      expect(NativeCameraNames.read(count: 2, name: reader.call), [
        'Camera 1',
        'Camera 2',
      ]);
    });

    test('a name written as nothing falls back rather than showing blank', () {
      expect(NativeCameraNames.at(0, _WritesNothing().call), 'Camera 1');
    });

    test('no cameras is an empty list, not an error', () {
      expect(
        NativeCameraNames.read(count: 0, name: _StubNames(const []).call),
        isEmpty,
      );
    });
  });

  group('the camera', () {
    test('a build with no encoder offers nothing', () async {
      final controller = _controllerFor(_FakeEncoder(supported: false));
      addTearDown(controller.dispose);

      expect(controller.isSupported, isFalse);
      expect(await controller.turnOn(), isFalse);
      expect(controller.error, isA<VideoEncoderException>());
    });

    test('a machine with no camera attached says so', () async {
      final controller = _controllerFor(_FakeEncoder(cameras: const []));
      addTearDown(controller.dispose);

      expect(controller.isSupported, isTrue);
      expect(controller.cameras, isEmpty);
      expect(await controller.turnOn(), isFalse);
      expect(
        (controller.error! as VideoEncoderException).failure,
        VideoEncoderFailure.noCamera,
      );
    });

    test('turning on declares, sends and announces', () async {
      final encoder = _FakeEncoder();
      final transport = _FakeVoiceVideoTransport();
      final announcements = <bool>[];
      final controller = _controllerFor(
        encoder,
        transport: transport,
        onAnnounce: announcements.add,
      );
      addTearDown(controller.dispose);

      expect(await controller.turnOn(), isTrue);

      expect(encoder.started.single.source, VideoCaptureSource.camera);
      expect(transport.announcements, [true]);
      expect(announcements, [true]);
      expect(controller.isOn, isTrue);
      expect(controller.isBusy, isFalse);

      // The pictures ride the voice socket, on the SSRC that was declared.
      encoder.emit();
      await Future<void>.delayed(Duration.zero);
      expect(controller.sentPackets, greaterThan(0));
      expect(transport.sentSsrcs.single, 41);
    });

    test('a camera asked for twice is only started once', () async {
      final encoder = _FakeEncoder();
      final controller = _controllerFor(
        encoder,
        transport: _FakeVoiceVideoTransport(),
      );
      addTearDown(controller.dispose);

      expect(await controller.turnOn(), isTrue);
      expect(await controller.turnOn(), isTrue);

      expect(encoder.started.length, 1);
    });

    test('a voice connection that is not ready refuses the camera', () async {
      final encoder = _FakeEncoder();
      final controller = _controllerFor(encoder);
      addTearDown(controller.dispose);

      expect(await controller.turnOn(), isFalse);

      expect(controller.error, isA<StateError>());
      expect(encoder.started, isEmpty);
    });

    test('a transport with no SSRC yet refuses the camera', () async {
      final encoder = _FakeEncoder();
      final controller = _controllerFor(
        encoder,
        transport: _FakeVoiceVideoTransport(audioSsrc: null),
      );
      addTearDown(controller.dispose);

      expect(await controller.turnOn(), isFalse);
      expect(encoder.started, isEmpty);
    });

    test('an encoder that will not open is reported, not thrown', () async {
      final encoder = _FakeEncoder()..failStart = true;
      final controller = _controllerFor(
        encoder,
        transport: _FakeVoiceVideoTransport(),
      );
      addTearDown(controller.dispose);

      expect(await controller.turnOn(), isFalse);

      expect(controller.error, isA<VideoEncoderException>());
      expect(controller.isOn, isFalse);
    });

    test('a gateway that refuses the flag stops the camera again', () async {
      final encoder = _FakeEncoder();
      final transport = _FakeVoiceVideoTransport();
      final controller = _controllerFor(
        encoder,
        transport: transport,
        accept: false,
      );
      addTearDown(controller.dispose);

      expect(await controller.turnOn(), isFalse);

      // Everything announced is taken back: an icon with nothing behind it is
      // worse than no icon.
      expect(transport.announcements, [true, false]);
      expect(encoder.stopped, 1);
      expect(controller.isOn, isFalse);
      expect(controller.error, isA<StateError>());
    });

    test('turning off tells the room before it stops encoding', () async {
      final encoder = _FakeEncoder();
      final transport = _FakeVoiceVideoTransport();
      final announcements = <bool>[];
      final controller = _controllerFor(
        encoder,
        transport: transport,
        onAnnounce: announcements.add,
      );
      addTearDown(controller.dispose);
      await controller.turnOn();

      await controller.turnOff();

      expect(announcements, [true, false]);
      expect(transport.announcements, [true, false]);
      expect(encoder.stopped, 1);
      expect(controller.isOn, isFalse);

      // Off already: nothing more is said.
      await controller.turnOff();
      expect(announcements.length, 2);
    });

    test('toggle answers what the camera ended up as', () async {
      final controller = _controllerFor(
        _FakeEncoder(),
        transport: _FakeVoiceVideoTransport(),
      );
      addTearDown(controller.dispose);

      expect(await controller.toggle(), isTrue);
      expect(await controller.toggle(), isFalse);
    });

    test('a dropped connection is forgotten rather than announced', () async {
      final encoder = _FakeEncoder();
      final transport = _FakeVoiceVideoTransport();
      final controller = _controllerFor(encoder, transport: transport);
      addTearDown(controller.dispose);
      await controller.turnOn();

      await controller.forget();

      // The socket that would carry the announcement is the one that went.
      expect(transport.announcements, [true]);
      expect(controller.isOn, isFalse);
      expect(encoder.stopped, 1);

      // Forgetting a camera that was already off does nothing at all.
      await controller.forget();
      expect(encoder.stopped, 1);
    });

    test('a second camera can be chosen', () async {
      final encoder = _FakeEncoder(cameras: const ['Front', 'Back']);
      final controller = _controllerFor(
        encoder,
        transport: _FakeVoiceVideoTransport(),
      );
      addTearDown(controller.dispose);

      expect(controller.selectedCamera, 0);
      controller.selectCamera(1);
      // A camera that is already selected, or an index that is not one, does
      // not disturb the setting.
      controller
        ..selectCamera(1)
        ..selectCamera(-1);
      expect(controller.selectedCamera, 1);

      await controller.turnOn();
      expect(encoder.started.single.displayIndex, 1);
      expect(encoder.started.single.bitrate, 1200000);
    });
  });

  group('the voice state', () {
    test('the camera flag rides the whole-state frame', () async {
      final signaling = _FakeSignaling();
      final controller = VoiceController(
        const NoopVoiceMediaService(),
        signalingServiceProvider: () => signaling,
        callServiceProvider: () => null,
      );
      addTearDown(controller.dispose);

      // Nothing is connected, so there is no session to announce into.
      expect(await controller.setCameraAnnounced(enabled: true), isFalse);
      expect(controller.isCameraOn, isFalse);

      await controller.connect(guildId: 'guild-1', channelId: 'channel-1');
      expect(await controller.setCameraAnnounced(enabled: true), isTrue);

      expect(controller.isCameraOn, isTrue);
      expect(signaling.joins.last.$3, isTrue);

      // Asked for what it already is: no second frame.
      final sent = signaling.joins.length;
      expect(await controller.setCameraAnnounced(enabled: true), isTrue);
      expect(signaling.joins.length, sent);

      // And a mute after the camera keeps the camera on, because opcode 4
      // carries both.
      await controller.toggleMute();
      expect(signaling.joins.last.$3, isTrue);
    });
  });

  group('the button', () {
    testWidgets('a build with no encoder draws no camera button', (
      tester,
    ) async {
      await _pumpBar(tester, _controllerFor(_FakeEncoder(supported: false)));

      expect(find.byKey(const ValueKey('voice-bar-camera')), findsNothing);
    });

    testWidgets('a machine with no camera keeps the button and disables it', (
      tester,
    ) async {
      await _pumpBar(tester, _controllerFor(_FakeEncoder(cameras: const [])));

      final button = find.byKey(const ValueKey('voice-bar-camera'));
      expect(button, findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip).at(0)).message,
        isNotNull,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam), findsNothing);
    });

    testWidgets('the button turns the camera on and back off', (tester) async {
      final camera = _controllerFor(
        _FakeEncoder(),
        transport: _FakeVoiceVideoTransport(),
      );
      await _pumpBar(tester, camera);

      await tester.tap(find.byKey(const ValueKey('voice-bar-camera')));
      await tester.pumpAndSettle();
      expect(camera.isOn, isTrue);
      expect(find.byIcon(Icons.videocam), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('voice-bar-camera')));
      await tester.pumpAndSettle();
      expect(camera.isOn, isFalse);
      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
    });
  });
}

const _credentials = VoiceServerCredentials(
  guildId: 'guild-1',
  channelId: 'channel-1',
  userId: 'user-1',
  sessionId: 'session-1',
  token: 'token',
  endpoint: 'voice.example',
);

/// The camera profile as announce payload: these tests exercise the frame and
/// the announce path, so any settings answer, and the bitrate comes from the
/// quality home rather than being named again here.
const _cameraProfile = VideoEncoderSettings.camera(
  bitrate: StreamQualitySettings.defaultCameraBitrate,
);

SelfVideoController _controllerFor(
  _FakeEncoder encoder, {
  _FakeVoiceVideoTransport? transport,
  bool accept = true,
  void Function(bool)? onAnnounce,
}) => SelfVideoController(
  capture: VideoCaptureHub(encoder: encoder),
  transportProvider: () => transport,
  sinkProvider: () => transport?.send,
  announceSelfVideo: ({required bool enabled}) async {
    onAnnounce?.call(enabled);
    return accept;
  },
);

Future<void> _pumpBar(WidgetTester tester, SelfVideoController camera) async {
  final signaling = _FakeSignaling();
  final controller = VoiceController(
    const NoopVoiceMediaService(),
    signalingServiceProvider: () => signaling,
    callServiceProvider: () => null,
  );
  addTearDown(controller.dispose);
  addTearDown(camera.dispose);
  await controller.connect(guildId: 'guild-1', channelId: 'channel-1');
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([controller, camera]),
          builder: (_, _) => VoiceConnectionBar(
            controller: controller,
            channelNameFor: (_) => 'General',
            camera: camera,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeEncoder implements VideoEncoderService {
  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  _FakeEncoder({this.supported = true, this.cameras = const ['Webcam']});

  final bool supported;
  final List<String> cameras;
  final List<VideoEncoderSettings> started = [];
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();
  int stopped = 0;
  bool failStart = false;

  void emit() => _frames.add(
    EncodedVideoFrame(
      // A start code and a NAL header: enough for the packetiser to build one
      // single-unit packet from.
      bytes: Uint8List.fromList([0, 0, 0, 1, 0x65, 1, 2, 3]),
      timestamp: Duration.zero,
      isKeyframe: true,
    ),
  );

  @override
  bool get isSupported => supported;

  @override
  int get displayCount => 1;

  @override
  List<String> get cameraNames => cameras;

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start(VideoEncoderSettings settings) async {
    if (failStart) {
      throw const VideoEncoderException(VideoEncoderFailure.encoder);
    }
    started.add(settings);
  }

  @override
  Future<void> requestKeyframe() async {}

  @override
  Future<void> setPaused({required bool paused}) async {}

  @override
  Future<void> stop() async => stopped++;
}

final class _FakeVoiceVideoTransport implements VoiceVideoTransport {
  _FakeVoiceVideoTransport({this.audioSsrc = 40});

  @override
  final int? audioSsrc;

  final List<bool> announcements = [];
  final List<int> sentSsrcs = [];

  int send(DiscordRtpFrame frame) {
    sentSsrcs.add(frame.header.ssrc);
    return frame.payload.length;
  }

  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    announcements.add(enabled);
    return true;
  }
}

final class _FakeSignaling
    implements VoiceSignalingService, VoiceAudioTransport {
  @override
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.disconnected;

  @override
  VoiceTransportSession? currentSession;

  final List<(String, String, bool)> joins = [];
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _remoteAudio =
      StreamController.broadcast();
  final StreamController<void> _seated = StreamController.broadcast();

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _remoteAudio.stream;

  @override
  void sendOpusFrame(Uint8List opusFrame) {}

  @override
  Future<void> finishSpeaking() async {}

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => const {};

  @override
  Stream<void> get seatedChanges => _seated.stream;

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) async => joins.add((guildId, channelId, selfVideo));

  @override
  Future<void> leaveVoiceChannel(String guildId) async {}
}

/// Stands in for `flucord_video_camera_name`, writing UTF-8 into the buffer
/// the way the native side does.
final class _StubNames {
  _StubNames(this.names, {this.refuse = const {}});

  final List<String> names;
  final Set<int> refuse;
  int sizings = 0;

  int call(int index, Pointer<Utf8> buffer, int capacity) {
    if (index >= names.length) return 0;
    final bytes = utf8.encode(names[index]);
    final needed = bytes.length + 1;
    if (capacity == 0) {
      sizings++;
      return needed;
    }
    if (refuse.contains(index)) return -1;
    final target = buffer.cast<Uint8>().asTypedList(capacity);
    target.setRange(0, bytes.length, bytes);
    target[bytes.length] = 0;
    return needed;
  }
}

/// Claims a length and then writes an empty string, which would otherwise put
/// a blank row in the picker.
final class _WritesNothing {
  int call(int index, Pointer<Utf8> buffer, int capacity) {
    if (capacity == 0) return 8;
    buffer.cast<Uint8>().asTypedList(capacity)[0] = 0;
    return 8;
  }
}
