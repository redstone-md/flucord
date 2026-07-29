import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_audio.dart';
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

  test(
    'gates Opus uplink on transport readiness and ends speech first',
    () async {
      final operations = <String>[];
      final media = _FakeVoiceMediaService(operations: operations);
      final signaling = _FakeVoiceSignalingService(operations: operations);
      final controller = VoiceController(
        media,
        signalingServiceProvider: () => signaling,
        audioCodecFactory: _FakeCodecFactory(),
      );
      addTearDown(controller.dispose);
      addTearDown(signaling.close);

      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
      media.addPcm(Uint8List(3840));
      await _flushEvents();
      expect(signaling.sentFrames, isEmpty);

      signaling.emit(const VoiceTransportReadyEvent(_transportSession));
      await _flushEvents();
      expect(controller.isAudioUplinkActive, isTrue);
      media.addPcm(Uint8List(3840));
      await _flushEvents();
      expect(signaling.sentFrames, hasLength(1));

      operations.clear();
      await controller.toggleMute();
      expect(operations, ['microphone:false', 'finish']);
      expect(controller.isAudioUplinkActive, isFalse);

      await controller.toggleMute();
      media.addPcm(Uint8List(3840));
      await _flushEvents();
      operations.clear();
      await controller.disconnect();
      expect(operations.take(2), ['finish', 'leave']);
      expect(controller.isAudioUplinkActive, isFalse);
    },
  );

  test(
    'routes decoded voice to native playback and its output devices',
    () async {
      final media = _FakeVoiceMediaService();
      final signaling = _FakeVoiceSignalingService();
      final playback = _FakeVoicePlaybackService();
      final controller = VoiceController(
        media,
        signalingServiceProvider: () => signaling,
        audioCodecFactory: _FakeCodecFactory(),
        playbackService: playback,
      );
      addTearDown(controller.dispose);
      addTearDown(signaling.close);

      await controller.initialize();
      expect(playback.initialized, isTrue);
      expect(controller.outputDevices.map((device) => device.id), [
        'output-default',
        'output-headset',
      ]);
      expect(controller.selectedOutputId, 'output-default');
      await controller.selectOutput('output-headset');
      expect(playback.selectedOutput, 'output-headset');
      expect(media.selectedOutput, isNull);

      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
      signaling.emit(const VoiceTransportReadyEvent(_transportSession));
      await _flushEvents();
      expect(controller.isAudioPlaybackActive, isTrue);
      signaling.addRemote('user-1', [7]);
      await _flushEvents();
      expect(playback.frames.single.userId, 'user-1');

      await controller.toggleMute();
      expect(controller.isAudioPlaybackActive, isTrue);
      await controller.disconnect();
      expect(controller.isAudioPlaybackActive, isFalse);
    },
  );

  test('surfaces a background playback startup failure', () async {
    final signaling = _FakeVoiceSignalingService();
    final playback = _FakeVoicePlaybackService()..failOnEnable = true;
    final controller = VoiceController(
      _FakeVoiceMediaService(),
      signalingServiceProvider: () => signaling,
      audioCodecFactory: _FakeCodecFactory(),
      playbackService: playback,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
    signaling.emit(const VoiceTransportReadyEvent(_transportSession));
    await _flushEvents();
    await _flushEvents();

    expect(controller.error, isA<StateError>());
    expect(controller.isAudioPlaybackActive, isFalse);
  });

  test('joins and listens when the microphone will not open', () async {
    final media = _FakeVoiceMediaService()..failMicrophone = true;
    final signaling = _FakeVoiceSignalingService();
    final controller = VoiceController(
      media,
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'forge', channelId: 'forge-voice');

    // A machine with no working capture device still belongs in the room: it
    // can hear everyone, and refusing the join left it with neither.
    expect(controller.isConnected, isTrue);
    expect(signaling.joins.single.$2, 'forge-voice');
    expect(controller.microphoneError, isNotNull);
    expect(controller.joinBlockedReason, isNull);
  });

  test('a session with no voice transport says why it cannot join', () async {
    final media = _FakeVoiceMediaService();
    final controller = VoiceController(media);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.joinBlockedReason, isNotNull);
  });
}

const _transportSession = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 42,
  address: '203.0.113.7',
  port: 50000,
  mode: 'aead_xchacha20_poly1305_rtpsize',
  secretKey: [1, 2, 3],
  daveProtocolVersion: 1,
);

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _FakeVoiceSignalingService
    implements VoiceSignalingService, VoiceAudioTransport {
  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => const {};

  @override
  Stream<void> get seatedChanges => const Stream<void>.empty();

  _FakeVoiceSignalingService({this._operations});

  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _remoteAudio =
      StreamController.broadcast();
  final List<String>? _operations;
  final List<(String, String, bool)> joins = [];
  final List<String> leftGuilds = [];
  final List<Uint8List> sentFrames = [];

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _remoteAudio.stream;

  void emit(VoiceSignalingEvent event) => _events.add(event);

  void addRemote(String userId, List<int> opus) => _remoteAudio.add(
    VoiceRemoteOpusFrame(userId: userId, opus: Uint8List.fromList(opus)),
  );

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) async {
    joins.add((guildId, channelId, selfMute));
  }

  @override
  Future<void> leaveVoiceChannel(String guildId) async {
    leftGuilds.add(guildId);
    _operations?.add('leave');
  }

  @override
  void sendOpusFrame(Uint8List opusFrame) {
    sentFrames.add(Uint8List.fromList(opusFrame));
    _operations?.add('send');
  }

  @override
  Future<void> finishSpeaking() async => _operations?.add('finish');

  Future<void> close() async {
    await _events.close();
    await _remoteAudio.close();
  }
}

final class _FakeVoiceMediaService implements VoiceMediaService {
  _FakeVoiceMediaService({this._operations});

  final StreamController<void> _screenEnded = StreamController.broadcast();
  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();
  final List<String>? _operations;
  final List<String?> startedInputs = [];
  bool failMicrophone = false;
  bool microphoneEnabled = true;
  bool microphoneStopped = false;
  bool screenStopped = false;
  String? selectedOutput;
  String? sharedSource;

  void endScreenShare() => _screenEnded.add(null);

  void addPcm(Uint8List bytes) => _microphone.add(
    VoicePcmChunk(bytes: bytes, sampleRate: 48000, channels: 2),
  );

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
    _operations?.add('microphone:$enabled');
  }

  @override
  Future<void> startMicrophone(String? deviceId) async {
    startedInputs.add(deviceId);
    if (failMicrophone) throw StateError('no capture device');
  }

  @override
  Future<void> startScreenShare(String sourceId) async {
    sharedSource = sourceId;
  }

  @override
  Future<void> stopMicrophone() async {
    microphoneStopped = true;
    _operations?.add('microphone:stop');
  }

  @override
  Future<void> stopScreenShare() async {
    screenStopped = true;
    _operations?.add('screen:stop');
  }

  @override
  Future<void> dispose() async {
    await _screenEnded.close();
    await _microphone.close();
  }
}

final class _FakeCodecFactory implements VoiceOpusCodecFactory {
  @override
  VoiceOpusDecoder createDecoder() => _FakeDecoder();

  @override
  VoiceOpusEncoder createEncoder() => _FakeEncoder();
}

final class _FakeEncoder implements VoiceOpusEncoder {
  @override
  Uint8List encode(Int16List pcm) => Uint8List.fromList([pcm.length & 0xff]);

  @override
  void dispose() {}
}

final class _FakeDecoder implements VoiceOpusDecoder {
  @override
  Int16List decode(Uint8List opusFrame) =>
      Int16List.fromList([opusFrame.first, opusFrame.first]);

  @override
  Int16List decodeFec(Uint8List opusFrame, {int frameDurationMs = 20}) =>
      Int16List(0);

  @override
  Int16List conceal({int frameDurationMs = 20}) => Int16List(0);

  @override
  void dispose() {}
}

final class _FakeVoicePlaybackService implements VoiceAudioPlaybackService {
  bool initialized = false;
  bool enabled = false;
  bool disposed = false;
  bool failOnEnable = false;
  String? selectedOutput;
  final List<VoiceRemotePcmFrame> frames = [];

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<List<VoiceDevice>> enumerateOutputDevices() async => const [
    VoiceDevice(
      id: 'output-default',
      label: 'Default output',
      kind: VoiceDeviceKind.audioOutput,
    ),
    VoiceDevice(
      id: 'output-headset',
      label: 'Headset',
      kind: VoiceDeviceKind.audioOutput,
    ),
  ];

  @override
  Future<void> selectOutput(String deviceId) async {
    selectedOutput = deviceId;
  }

  @override
  Future<void> setEnabled(bool value) async {
    if (value && failOnEnable) throw StateError('Playback device disappeared');
    enabled = value;
  }

  @override
  void addPcmFrame(VoiceRemotePcmFrame frame) => frames.add(frame);

  @override
  Future<void> dispose() async => disposed = true;
}
