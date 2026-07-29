import 'dart:async';

import 'package:flucord/src/application/voice_controller.dart';
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

    test('a second initialise on a working session asks nothing again',
        () async {
      final media = _FakeMedia();
      final controller = VoiceController(media);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.initialize();

      expect(media.initialisations, 1);
    });

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
          ..failure = StateError(
            'first line\nsecond line\nthird line',
          ),
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
  Object? get previewRenderer => null;

  @override
  Stream<VoicePcmChunk> get microphonePcm => const Stream.empty();

  @override
  Stream<void> get screenShareEnded => const Stream.empty();

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async => const [];

  @override
  Future<void> startScreenShare(String sourceId) async {}

  @override
  Future<void> stopScreenShare() async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> dispose() async {}
}

final class _FakeSignaling implements VoiceSignalingService {
  // Open rather than an empty stream: an empty one closes immediately, and
  // the controller quite correctly reads a closed event stream as the
  // transport having gone away.
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<void> _seated = StreamController.broadcast();

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
  }) async {}

  @override
  Future<void> leaveVoiceChannel(String guildId) async {}
}
