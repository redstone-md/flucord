import 'dart:async';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/presentation/widgets/voice_room_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('devices that would not open', () {
    test('a failure is tried again rather than remembered forever', () async {
      final media = _FakeMedia()..failNext = true;
      final controller = VoiceController(media);
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.state, VoiceState.failure);
      expect(controller.deviceError, isNotNull);

      // A headset gets plugged in, or an exclusive-mode application lets go.
      // The old behaviour returned early for the rest of the session and kept
      // showing the first error over every later attempt.
      media.failNext = false;
      await controller.retryDevices();

      expect(controller.state, VoiceState.ready);
      expect(controller.deviceError, isNull);
      expect(controller.error, isNull);
      expect(media.initialisations, 2);
    });

    test(
      'a second initialise on a working session asks nothing again',
      () async {
        final media = _FakeMedia();
        final controller = VoiceController(media);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.initialize();

        expect(media.initialisations, 1);
      },
    );

    test('a retry while one is running does not start a second', () async {
      final media = _FakeMedia()..hold = true;
      final controller = VoiceController(media);
      addTearDown(controller.dispose);

      final first = controller.initialize();
      await controller.retryDevices();
      media.release();
      await first;

      expect(media.initialisations, 1);
    });
  });

  group('binding to a connection that is already up', () {
    test('a rebind keeps the connection it found', () async {
      var signaling = _FakeSignaling();
      final controller = VoiceController(
        _FakeMedia(),
        signalingServiceProvider: () => signaling,
      );
      addTearDown(controller.dispose);
      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
      expect(controller.connectionStatus, VoiceConnectionStatus.joining);

      // The transport comes up, and then something replaces the service —
      // which the app does whenever the chat session is rebuilt. The `ready`
      // had already been announced and nothing announces it twice, so a
      // controller that waited for one showed a working call as joining
      // forever.
      signaling = _FakeSignaling()..currentStatus = VoiceConnectionStatus.ready;
      await controller.refreshSignalingService();

      expect(controller.connectionStatus, VoiceConnectionStatus.ready);
    });

    test(
      'a rebind onto a service that is not connected still says joining',
      () async {
        var signaling = _FakeSignaling();
        final controller = VoiceController(
          _FakeMedia(),
          signalingServiceProvider: () => signaling,
        );
        addTearDown(controller.dispose);
        await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

        signaling = _FakeSignaling();
        await controller.refreshSignalingService();

        expect(controller.connectionStatus, VoiceConnectionStatus.joining);
      },
    );
  });

  group('a bind whose audio will not start', () {
    test('still hears the transport it bound to', () async {
      final signaling = _FakeSignaling();
      final controller = VoiceController(
        _FakeMedia(),
        signalingServiceProvider: () => signaling,
        playbackService: _RefusingPlayback(),
      );
      addTearDown(controller.dispose);

      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
      signaling.announce(
        const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready),
      );
      await Future<void>.delayed(Duration.zero);

      // The bind used to set the service and then throw on its way to the
      // subscription, so every later bind took the "already bound" exit and
      // the controller never heard another word from a transport that was
      // carrying audio the whole time.
      expect(controller.connectionStatus, VoiceConnectionStatus.ready);
    });
  });

  group('who the room shows', () {
    test('renders the people seated in it, announced or not', () async {
      final signaling = _FakeSignaling()
        ..seated = {
          'voice-1': const [
            VoiceParticipantStateEvent(
              userId: 'user-1',
              guildId: 'guild-1',
              channelId: 'voice-1',
              selfMuted: true,
              selfDeafened: false,
              serverMuted: false,
              serverDeafened: false,
              isStreaming: true,
              isVideoEnabled: false,
            ),
          ],
        };
      final controller = VoiceController(
        _FakeMedia(),
        signalingServiceProvider: () => signaling,
      );
      addTearDown(controller.dispose);

      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

      // Nobody announced them: arrivals are announcements, and a client that
      // reconnected — or re-entered a channel it was already in — is sent none
      // for the people who were already there. The room rendered empty while
      // the sidebar plainly listed four people in it.
      expect(controller.participants, hasLength(1));
      expect(controller.participants.single.userId, 'user-1');
      expect(controller.participants.single.isMuted, isTrue);
      expect(controller.participants.single.isStreaming, isTrue);
    });

    test('keeps somebody the transport saw before the roster did', () async {
      final signaling = _FakeSignaling();
      final controller = VoiceController(
        _FakeMedia(),
        signalingServiceProvider: () => signaling,
      );
      addTearDown(controller.dispose);
      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

      signaling.announce(
        const VoiceParticipantStateEvent(
          userId: 'user-2',
          guildId: 'guild-1',
          channelId: 'voice-1',
          selfMuted: false,
          selfDeafened: false,
          serverMuted: false,
          serverDeafened: false,
          isStreaming: false,
          isVideoEnabled: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.participants.single.userId, 'user-2');
    });
  });

  group('what the room says is wrong', () {
    test('a device failure says so, and carries the reason', () async {
      final signaling = _FakeSignaling();
      final controller = VoiceController(
        _FakeMedia()..failNext = true,
        signalingServiceProvider: () => signaling,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

      final warning = voiceRoomWarning(controller);

      // The old wording called every failure "Media device unavailable",
      // which sent somebody to check a headset that was working.
      expect(warning, contains('Audio devices could not be opened'));
      expect(warning, contains('no audio devices'));
      expect(voiceRoomOffersDeviceRetry(controller), isTrue);
    });

    test('a room with nothing wrong says nothing', () async {
      final signaling = _FakeSignaling();
      final controller = VoiceController(
        _FakeMedia(),
        signalingServiceProvider: () => signaling,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(voiceRoomWarning(controller), isNull);
      expect(voiceRoomOffersDeviceRetry(controller), isFalse);
    });

    test('a platform exception is trimmed to its first line', () async {
      final signaling = _FakeSignaling();
      final controller = VoiceController(
        _FakeMedia()
          ..failNext = true
          ..failure = StateError('first line\nsecond line\nthird line'),
        signalingServiceProvider: () => signaling,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

      final warning = voiceRoomWarning(controller)!;

      // A paragraph of stack in a status strip pushes the room off screen.
      expect(warning, contains('first line'));
      expect(warning, isNot(contains('second line')));
    });

    test('a very long line is cut rather than filling the strip', () async {
      final signaling = _FakeSignaling();
      final controller = VoiceController(
        _FakeMedia()
          ..failNext = true
          ..failure = StateError('x' * 400),
        signalingServiceProvider: () => signaling,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

      expect(voiceRoomWarning(controller)!.length, lessThan(220));
    });
  });
}

final class _RefusingPlayback implements VoiceAudioPlaybackService {
  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateOutputDevices() async => const [];

  @override
  Future<void> selectOutput(String deviceId) async {}

  @override
  Future<void> setEnabled(bool enabled) async =>
      throw StateError('no playback device');

  @override
  void addPcmFrame(VoiceRemotePcmFrame frame) {}

  @override
  Future<void> dispose() async {}
}

final class _FakeMedia implements VoiceMediaService {
  bool failNext = false;
  bool hold = false;
  Object failure = StateError('no audio devices');
  int initialisations = 0;
  Completer<void>? _gate;

  void release() => _gate?.complete();

  @override
  Future<void> initialize() async {
    initialisations++;
    if (hold) {
      final gate = _gate = Completer<void>();
      await gate.future;
    }
    if (failNext) throw failure;
  }

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [
    VoiceDevice(
      id: 'mic-1',
      label: 'Microphone',
      kind: VoiceDeviceKind.audioInput,
    ),
    VoiceDevice(
      id: 'speaker-1',
      label: 'Speakers',
      kind: VoiceDeviceKind.audioOutput,
    ),
  ];

  @override
  Stream<VoicePcmChunk> get microphonePcm => const Stream.empty();

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> dispose() async {}
}

final class _FakeSignaling implements VoiceSignalingService {
  @override
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.disconnected;

  @override
  VoiceTransportSession? currentSession;

  // Open rather than an empty stream: an empty one closes immediately, and
  // the controller quite correctly reads a closed event stream as the
  // transport having gone away.
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  void announce(VoiceSignalingEvent event) => _events.add(event);
  final StreamController<void> _seated = StreamController.broadcast();

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  Map<String, List<VoiceParticipantStateEvent>> seated = const {};

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => seated;

  @override
  Stream<void> get seatedChanges => _seated.stream;

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
