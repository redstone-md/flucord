import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/domain/voice_processing.dart';

import 'support/fake_voice_audio.dart';

void main() {
  test('a participant with no chosen level plays at the room level', () async {
    final repository = MemoryVoiceProcessingRepository(
      const VoiceProcessingSettings(),
    );
    final playback = _RecordingPlayback();
    final harness = _Harness(playback: playback, repository: repository);
    addTearDown(harness.dispose);
    final controller = harness.controller;

    await controller.loadProcessingSettings();

    expect(controller.volumeFor('user-1'), 1);
    expect(playback.sourceVolumes, isEmpty);
  });

  test('a saved level is applied to playback before anyone speaks', () async {
    final repository = MemoryVoiceProcessingRepository(
      const VoiceProcessingSettings(
        listening: VoiceListeningSettings(participantVolumes: {'user-1': 0.4}),
      ),
    );
    final playback = _RecordingPlayback();
    final harness = _Harness(playback: playback, repository: repository);
    addTearDown(harness.dispose);
    final controller = harness.controller;

    await controller.loadProcessingSettings();

    expect(controller.volumeFor('user-1'), 0.4);
    expect(playback.sourceVolumes['user-1'], 0.4);
  });

  test('setting a level routes to that participant alone', () async {
    final playback = _RecordingPlayback();
    final harness = _Harness(playback: playback);
    addTearDown(harness.dispose);
    final controller = harness.controller;

    await controller.setParticipantVolume('user-1', 0.25);

    expect(playback.sourceVolumes, {'user-1': 0.25});
    expect(controller.volumeFor('user-1'), 0.25);
    expect(controller.volumeFor('user-2'), 1);

    await controller.setParticipantVolume('user-2', 0.9);
    expect(playback.sourceVolumes, {'user-1': 0.25, 'user-2': 0.9});
  });

  test(
    'a level is saved for the next session, clamped to the slider range',
    () async {
      final repository = MemoryVoiceProcessingRepository();
      final harness = _Harness(repository: repository);
      addTearDown(harness.dispose);
      final controller = harness.controller;

      await controller.setParticipantVolume('user-1', 2);
      expect(controller.volumeFor('user-1'), 1);

      await controller.setParticipantVolume('user-2', -0.5);
      expect(controller.volumeFor('user-2'), 0);

      final saved = repository.saved;
      expect(saved, isNotNull);
      // Full level is stored as no entry: it is the room's default.
      expect(saved!.listening.participantVolumes, {'user-2': 0.0});
      expect(controller.volumeFor('user-1'), 1);
    },
  );

  test(
    'a participant turned back to full level is remembered as the default',
    () async {
      final repository = MemoryVoiceProcessingRepository(
        const VoiceProcessingSettings(
          listening: VoiceListeningSettings(
            participantVolumes: {'user-1': 0.4},
          ),
        ),
      );
      final playback = _RecordingPlayback();
      final harness = _Harness(playback: playback, repository: repository);
      addTearDown(harness.dispose);
      final controller = harness.controller;

      await controller.loadProcessingSettings();
      await controller.setParticipantVolume('user-1', 1);

      // The default is not stored as a per-participant entry: a participant
      // nobody has turned up or down has no entry at all.
      expect(repository.saved!.listening.participantVolumes, isEmpty);
      expect(playback.sourceVolumes['user-1'], 1);
    },
  );

  test('speech turns other applications down and back up', () async {
    final attenuation = _RecordingAttenuation();
    final harness = _Harness(
      attenuation: attenuation,
      repository: MemoryVoiceProcessingRepository(
        const VoiceProcessingSettings(
          listening: VoiceListeningSettings(
            attenuateApplications: true,
            attenuationLevel: 0.8,
          ),
        ),
      ),
    );
    addTearDown(harness.dispose);
    final controller = harness.controller;

    await controller.loadProcessingSettings();
    expect(controller.attenuateApplications, isTrue);
    expect(controller.attenuationLevel, 0.8);
    expect(attenuation.calls, isEmpty);

    // A loud frame opens the gate, which is what announces speech.
    await _connect(harness);
    harness.media.addPcm(_speech);
    await _flushEvents();
    expect(attenuation.calls, ['attenuate:0.80']);
    expect(attenuation.calls, isNot(contains('release')));

    // Quiet frames run the hangover out, which announces the end.
    for (var i = 0; i < 25; i++) {
      harness.media.addPcm(_silence);
    }
    await _flushEvents();
    expect(attenuation.calls, ['attenuate:0.80', 'release']);
  });

  test('the attenuation switch going off releases the machine', () async {
    final attenuation = _RecordingAttenuation();
    final harness = _Harness(
      attenuation: attenuation,
      repository: MemoryVoiceProcessingRepository(
        const VoiceProcessingSettings(
          listening: VoiceListeningSettings(attenuateApplications: true),
        ),
      ),
    );
    addTearDown(harness.dispose);
    final controller = harness.controller;

    await controller.loadProcessingSettings();
    await _connect(harness);
    harness.media.addPcm(_speech);
    await _flushEvents();
    expect(attenuation.calls, ['attenuate:0.80']);

    await controller.setAttenuateApplications(false);
    expect(controller.attenuateApplications, isFalse);
    expect(attenuation.calls, ['attenuate:0.80', 'release']);

    // Speech after the switch goes off does not attenuate.
    harness.media.addPcm(_speech);
    await _flushEvents();
    expect(attenuation.calls, ['attenuate:0.80', 'release']);
  });

  test('a level of nothing attenuates nothing', () async {
    final attenuation = _RecordingAttenuation();
    final harness = _Harness(
      attenuation: attenuation,
      repository: MemoryVoiceProcessingRepository(
        const VoiceProcessingSettings(
          listening: VoiceListeningSettings(
            attenuateApplications: true,
            attenuationLevel: 0,
          ),
        ),
      ),
    );
    addTearDown(harness.dispose);
    final controller = harness.controller;

    await controller.loadProcessingSettings();
    await _connect(harness);
    harness.media.addPcm(_speech);
    await _flushEvents();

    expect(attenuation.calls, isEmpty);
  });

  test('the level and switch persist for the next session', () async {
    final repository = MemoryVoiceProcessingRepository();
    final harness = _Harness(repository: repository);
    addTearDown(harness.dispose);
    final controller = harness.controller;

    await controller.setAttenuateApplications(true);
    await controller.setAttenuationLevel(0.5);

    final saved = repository.saved!.listening;
    expect(saved.attenuateApplications, isTrue);
    expect(saved.attenuationLevel, 0.5);
  });

  test(
    'a slow startup load does not overwrite a fresh participant level',
    () async {
      final repository = MemoryVoiceProcessingRepository()
        ..pendingLoad = Completer();
      final playback = _RecordingPlayback();
      final harness = _Harness(playback: playback, repository: repository);
      addTearDown(harness.dispose);
      final controller = harness.controller;

      final loading = controller.loadProcessingSettings();
      await controller.setParticipantVolume('user-1', 0.25);
      repository.pendingLoad!.complete(
        const VoiceProcessingSettings(
          listening: VoiceListeningSettings(
            participantVolumes: {'user-1': 0.9},
          ),
        ),
      );
      await loading;

      // The load had nothing the user had not already chosen past: the level
      // on the slider, and the one the service plays at, keep the new value.
      expect(controller.volumeFor('user-1'), 0.25);
      expect(playback.sourceVolumes['user-1'], 0.25);
      expect(repository.saved!.listening.participantVolumes, {'user-1': 0.25});
    },
  );

  test(
    'a slow startup load does not overwrite a fresh attenuation switch',
    () async {
      final repository = MemoryVoiceProcessingRepository()
        ..pendingLoad = Completer();
      final attenuation = _RecordingAttenuation();
      final harness = _Harness(
        attenuation: attenuation,
        repository: repository,
      );
      addTearDown(harness.dispose);
      final controller = harness.controller;

      final loading = controller.loadProcessingSettings();
      await controller.setAttenuateApplications(true);
      await controller.setAttenuationLevel(0.6);
      repository.pendingLoad!.complete(const VoiceProcessingSettings());
      await loading;

      expect(controller.attenuateApplications, isTrue);
      expect(controller.attenuationLevel, 0.6);
      expect(repository.saved!.listening.attenuateApplications, isTrue);
      expect(repository.saved!.listening.attenuationLevel, 0.6);
    },
  );

  test('an unsupported machine reports the switch as unavailable', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    expect(harness.controller.isApplicationAttenuationAvailable, isFalse);
  });

  test('stored listening preferences survive a hand-edited file', () {
    // A level that is not a number keeps the room's default; unknown keys
    // are left where a newer build put them.
    final read = VoiceListeningSettings.fromJson({
      'participant_volumes': {'user-1': 0.3, 'user-2': 'loud'},
      'attenuate_applications': true,
      'attenuation_level': 1.5,
    });

    expect(read.volumeFor('user-1'), 0.3);
    expect(read.volumeFor('user-2'), 1);
    expect(read.attenuateApplications, isTrue);
    expect(read.attenuationLevel, 1);

    // Round trip: what is saved is what loads back.
    final restored = VoiceListeningSettings.fromJson(read.toJson());
    expect(restored, read);
  });

  test('processing settings keep both halves through one document', () {
    const settings = VoiceProcessingSettings(
      noiseSuppression: true,
      listening: VoiceListeningSettings(
        participantVolumes: {'user-1': 0.2},
        attenuateApplications: true,
        attenuationLevel: 0.6,
      ),
    );
    final restored = VoiceProcessingSettings.fromJson(settings.toJson());

    expect(restored, settings);
  });

  test('capture settings keep all four through one document', () {
    const settings = VoiceProcessingSettings(
      inputSensitivity: -42.5,
      pushToTalkReleaseDelayMs: 150,
      echoCancellation: false,
      automaticGainControl: false,
    );
    final restored = VoiceProcessingSettings.fromJson(settings.toJson());

    expect(restored, settings);
    expect(restored.inputSensitivity, -42.5);
    expect(restored.pushToTalkReleaseDelayMs, 150);
    expect(restored.echoCancellation, isFalse);
    expect(restored.automaticGainControl, isFalse);
  });

  test('capture settings fall back per field on a hand-edited file', () {
    final read = VoiceProcessingSettings.fromJson({
      'noise_suppression': true,
      'input_sensitivity': 'loud',
      'push_to_talk_release_delay_ms': -20,
      'echo_cancellation': 'maybe',
      'automatic_gain_control': false,
    });

    // A sensitivity that is not a number is the automatic gate; a delay
    // below zero is no delay; a switch that is not a bool keeps the
    // default the machine ships with.
    expect(read.inputSensitivity, isNull);
    expect(read.pushToTalkReleaseDelayMs, 0);
    expect(read.echoCancellation, isTrue);
    expect(read.automaticGainControl, isFalse);
  });

  test('the automatic gate is saved as no sensitivity at all', () {
    final written = const VoiceProcessingSettings().toJson();

    // Absent rather than null: a file with the key left out is the same
    // file an older build wrote, and the switch back to automatic must
    // read as one.
    expect(written, isNot(contains('input_sensitivity')));
    expect(VoiceProcessingSettings.fromJson(written).inputSensitivity, isNull);
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

const _transportSession = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 42,
  address: '203.0.113.7',
  port: 50000,
  mode: 'aead_xchacha20_poly1305_rtpsize',
  secretKey: [1, 2, 3],
  daveProtocolVersion: 1,
);

/// Joins a room and brings the transport up, so the uplink is live and
/// frames reach the gate: without a transport, the uplink stays disabled
/// and the gate never sees a frame.
Future<void> _connect(_Harness harness) async {
  await harness.controller.connect(guildId: 'guild-1', channelId: 'voice-1');
  await _flushEvents();
  harness.signaling.emit(const VoiceTransportReadyEvent(_transportSession));
  await _flushEvents();
}

/// One 20 ms stereo frame loud enough to pass the uplink's gate.
final Uint8List _speech = Int16List.fromList(
  List.generate(1920, (index) => (index * 37) % 2000 - 1000),
).buffer.asUint8List();

/// One 20 ms stereo frame of nothing.
final Uint8List _silence = Int16List(1920).buffer.asUint8List();

final class _Harness {
  _Harness({
    _RecordingPlayback? playback,
    MemoryVoiceProcessingRepository? repository,
    _RecordingAttenuation? attenuation,
  }) {
    controller = VoiceController(
      media,
      signalingServiceProvider: () => signaling,
      audioCodecFactory: FakeVoiceOpusCodecFactory(),
      playbackService: playback,
      processingRepository: repository,
      applicationAttenuation: attenuation,
    );
  }

  final _FakeMedia media = _FakeMedia();
  final _FakeSignaling signaling = _FakeSignaling();

  late final VoiceController controller;

  Future<void> dispose() async {
    controller.dispose();
    await signaling.close();
  }
}

final class _RecordingPlayback implements VoiceAudioPlaybackService {
  final Map<String, double> sourceVolumes = {};
  bool enabled = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateOutputDevices() async => const [];

  @override
  Future<void> selectOutput(String deviceId) async {}

  @override
  Future<void> setEnabled(bool value) async => enabled = value;

  @override
  void addPcmFrame(VoiceRemotePcmFrame frame) {}

  @override
  Future<void> removeSource(String sourceId) async {}

  @override
  Future<void> setSourceVolume(String sourceId, double volume) async =>
      sourceVolumes[sourceId] = volume;

  @override
  Future<void> dispose() async {}
}

final class _RecordingAttenuation implements ApplicationAttenuation {
  final List<String> calls = [];

  @override
  bool get isSupported => true;

  @override
  Future<void> attenuate(double level) async =>
      calls.add('attenuate:${level.toStringAsFixed(2)}');

  @override
  Future<void> release() async => calls.add('release');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

final class _FakeSignaling
    implements VoiceSignalingService, VoiceAudioTransport {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _remoteAudio =
      StreamController.broadcast();
  final List<Uint8List> sentFrames = [];

  @override
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.disconnected;

  @override
  VoiceTransportSession? currentSession;

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => const {};

  @override
  Stream<void> get seatedChanges => const Stream.empty();

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _remoteAudio.stream;

  @override
  void sendOpusFrame(Uint8List frame) => sentFrames.add(frame);

  @override
  Future<void> finishSpeaking() async {}

  void emit(VoiceSignalingEvent event) => _events.add(event);

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

  Future<void> close() async {
    await _events.close();
    await _remoteAudio.close();
  }
}

final class _FakeMedia implements VoiceMediaService {
  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();

  void addPcm(Uint8List bytes) => _microphone.add(
    VoicePcmChunk(bytes: bytes, sampleRate: 48000, channels: 2),
  );

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphone.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [];

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> dispose() async {
    await _microphone.close();
  }
}
