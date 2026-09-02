import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/domain/voice_processing.dart';

import 'support/fake_voice_audio.dart';

void main() {
  test('push to talk sets the mute flag rather than toggling it', () async {
    final media = _FakeVoiceMediaService();
    final controller = VoiceController(media);
    addTearDown(controller.dispose);
    await controller.initialize();

    // Nothing is connected, so there is nothing to unmute into.
    await controller.setMuted(muted: true);
    expect(controller.isMuted, isFalse);

    await controller.connect(guildId: 'forge', channelId: 'forge-voice');
    await controller.setMuted(muted: true);
    expect(controller.isMuted, isTrue);
    expect(media.microphoneEnabled, isFalse);

    // Asked for what it already is: nothing further is sent.
    await controller.setMuted(muted: true);
    expect(controller.isMuted, isTrue);

    await controller.setMuted(muted: false);
    expect(controller.isMuted, isFalse);
    expect(media.microphoneEnabled, isTrue);
  });

  test('deafening also mutes, and undeafening leaves the mute alone', () async {
    final media = _FakeVoiceMediaService();
    final controller = VoiceController(media);
    addTearDown(controller.dispose);
    await controller.initialize();

    // Not connected: nothing to deafen.
    await controller.toggleDeafen();
    expect(controller.isDeafened, isFalse);

    await controller.connect(guildId: 'forge', channelId: 'forge-voice');
    await controller.toggleDeafen();

    expect(controller.isDeafened, isTrue);
    // Somebody who cannot hear the room should not still be speaking into it.
    expect(controller.isMuted, isTrue);
    expect(media.microphoneEnabled, isFalse);

    await controller.toggleDeafen();
    expect(controller.isDeafened, isFalse);
    expect(controller.isMuted, isTrue);
  });

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

    await controller.disconnect();
    expect(controller.isConnected, isFalse);
    expect(media.microphoneStopped, isTrue);
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
    'noise suppression is loaded, applied to the uplink and saved',
    () async {
      final media = _FakeVoiceMediaService();
      final signaling = _FakeVoiceSignalingService();
      final repository = MemoryVoiceProcessingRepository(
        const VoiceProcessingSettings(noiseSuppression: true),
      );
      final suppressor = FakeNoiseSuppressor();
      final controller = VoiceController(
        media,
        signalingServiceProvider: () => signaling,
        audioCodecFactory: _FakeCodecFactory(),
        noiseSuppressorFactory: () async => suppressor,
        processingRepository: repository,
      );
      addTearDown(controller.dispose);
      addTearDown(signaling.close);

      expect(controller.isNoiseSuppressionAvailable, isTrue);
      expect(controller.noiseSuppression, isFalse);
      await controller.loadProcessingSettings();
      await _flushEvents();
      expect(controller.noiseSuppression, isTrue);

      await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
      signaling.emit(const VoiceTransportReadyEvent(_transportSession));
      await _flushEvents();
      media.addPcm(_speech);
      await _flushEvents();
      expect(suppressor.frames, hasLength(1));

      await controller.setNoiseSuppression(false);
      expect(controller.noiseSuppression, isFalse);
      expect(repository.saved, const VoiceProcessingSettings());
      media.addPcm(_speech);
      await _flushEvents();
      expect(suppressor.frames, hasLength(1));
      expect(signaling.sentFrames, hasLength(2));
    },
  );

  test('a slow startup load does not overwrite a fresh toggle', () async {
    final repository = MemoryVoiceProcessingRepository()
      ..pendingLoad = Completer();
    final controller = VoiceController(
      _FakeVoiceMediaService(),
      audioCodecFactory: _FakeCodecFactory(),
      noiseSuppressorFactory: () async => FakeNoiseSuppressor(),
      processingRepository: repository,
    );
    addTearDown(controller.dispose);

    final loading = controller.loadProcessingSettings();
    await controller.setNoiseSuppression(true);
    repository.pendingLoad!.complete(const VoiceProcessingSettings());
    await loading;

    expect(controller.noiseSuppression, isTrue);
    expect(
      repository.saved,
      const VoiceProcessingSettings(noiseSuppression: true),
    );
  });

  test('a filter that will not open shows as off and reports why', () async {
    final controller = VoiceController(
      _FakeVoiceMediaService(),
      audioCodecFactory: _FakeCodecFactory(),
      noiseSuppressorFactory: () async => throw StateError('no df.dll'),
      processingRepository: MemoryVoiceProcessingRepository(),
    );
    addTearDown(controller.dispose);

    await controller.setNoiseSuppression(true);
    await _flushEvents();

    expect(controller.noiseSuppression, isFalse);
    expect(controller.error, isA<StateError>());
  });

  test('muting silences the uplink even when the microphone refuses', () async {
    final media = _FakeVoiceMediaService()..failMicrophoneToggle = true;
    final signaling = _FakeVoiceSignalingService();
    final controller = VoiceController(
      media,
      signalingServiceProvider: () => signaling,
      audioCodecFactory: _FakeCodecFactory(),
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);

    await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
    signaling.emit(const VoiceTransportReadyEvent(_transportSession));
    await _flushEvents();
    expect(controller.isAudioUplinkActive, isTrue);

    await controller.toggleMute();

    // One failing step used to skip every step after it, and the one that
    // stops the uplink was last: the button showed muted and the room heard
    // everything said into it.
    expect(controller.isMuted, isTrue);
    expect(controller.isAudioUplinkActive, isFalse);
    media.addPcm(_speech);
    await _flushEvents();
    expect(signaling.sentFrames, isEmpty);
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
      media.addPcm(_speech);
      await _flushEvents();
      expect(signaling.sentFrames, isEmpty);

      signaling.emit(const VoiceTransportReadyEvent(_transportSession));
      await _flushEvents();
      expect(controller.isAudioUplinkActive, isTrue);
      media.addPcm(_speech);
      await _flushEvents();
      expect(signaling.sentFrames, hasLength(1));

      operations.clear();
      await controller.toggleMute();
      // The uplink stops first. It is the one putting packets on the wire, so
      // it is the one whose failure would be heard.
      expect(operations, ['finish', 'microphone:false']);
      expect(controller.isAudioUplinkActive, isFalse);

      await controller.toggleMute();
      media.addPcm(_speech);
      await _flushEvents();
      operations.clear();
      await controller.disconnect();
      expect(operations.take(2), ['finish', 'leave']);
      expect(controller.isAudioUplinkActive, isFalse);
    },
  );

  test(
    'a participant speaks while their voice arrives, and a little after',
    () {
      fakeAsync((async) {
        final signaling = _FakeVoiceSignalingService();
        final playback = _FakeVoicePlaybackService();
        final streamAudio = StreamController<VoiceRemotePcmFrame>.broadcast();
        final controller = VoiceController(
          _FakeVoiceMediaService(),
          signalingServiceProvider: () => signaling,
          audioCodecFactory: _FakeCodecFactory(),
          playbackService: playback,
          streamAudio: streamAudio.stream,
        );
        addTearDown(streamAudio.close);
        addTearDown(controller.dispose);
        addTearDown(signaling.close);
        controller.connect(guildId: 'guild-1', channelId: 'voice-1');
        async.flushMicrotasks();
        signaling.emit(const VoiceTransportReadyEvent(_transportSession));
        async.flushMicrotasks();

        signaling.addRemote('user-1', [7]);
        async.flushMicrotasks();
        expect(controller.participants.single.isSpeaking, isTrue);

        // Frames keep coming: the ring stays on for as long as they do.
        const almost = Duration(milliseconds: 240);
        async.elapse(almost);
        signaling.addRemote('user-1', [7]);
        async.elapse(almost);
        expect(controller.participants.single.isSpeaking, isTrue);

        async.elapse(const Duration(milliseconds: 20));
        expect(controller.participants.single.isSpeaking, isFalse);

        // Screen-share audio is a game, not a voice.
        streamAudio.add(
          VoiceRemotePcmFrame(
            userId: 'user-1',
            sourceId: 'stream:guild:guild-1:voice-1:user-1',
            samples: Int16List.fromList([8]),
          ),
        );
        async.flushMicrotasks();
        expect(controller.participants.single.isSpeaking, isFalse);
      });
    },
  );

  test(
    'routes decoded voice to native playback and its output devices',
    () async {
      final media = _FakeVoiceMediaService();
      final signaling = _FakeVoiceSignalingService();
      final playback = _FakeVoicePlaybackService();
      final streamAudio = StreamController<VoiceRemotePcmFrame>.broadcast();
      final controller = VoiceController(
        media,
        signalingServiceProvider: () => signaling,
        audioCodecFactory: _FakeCodecFactory(),
        playbackService: playback,
        streamAudio: streamAudio.stream,
      );
      addTearDown(streamAudio.close);
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

      streamAudio.add(
        VoiceRemotePcmFrame(
          userId: 'user-1',
          sourceId: 'stream:guild:guild-1:voice-1:user-1',
          samples: Int16List.fromList([8]),
        ),
      );
      await _flushEvents();
      expect(playback.frames.map((frame) => frame.userId), [
        'user-1',
        'user-1',
      ]);
      expect(playback.frames.map((frame) => frame.sourceId), [
        'user-1',
        'stream:guild:guild-1:voice-1:user-1',
      ]);

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

  test('stopping a watched stream removes its playback source', () async {
    final playback = _FakeVoicePlaybackService();
    final ended = StreamController<String>.broadcast();
    addTearDown(ended.close);
    final controller = VoiceController(
      _FakeVoiceMediaService(),
      playbackService: playback,
      streamAudioEnded: ended.stream,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    ended.add('stream:call:dm-1:them:1');
    await _flushEvents();

    expect(playback.removedSources, ['stream:call:dm-1:them:1']);
  });

  test('a stream frame waits for room playback to become ready', () async {
    final playback = _FakeVoicePlaybackService();
    final signaling = _FakeVoiceSignalingService();
    final streamAudio = StreamController<VoiceRemotePcmFrame>.broadcast();
    addTearDown(streamAudio.close);
    addTearDown(signaling.close);
    final controller = VoiceController(
      _FakeVoiceMediaService(),
      signalingServiceProvider: () => signaling,
      playbackService: playback,
      streamAudio: streamAudio.stream,
    );
    addTearDown(controller.dispose);

    await controller.connect(guildId: 'guild-1', channelId: 'voice-1');
    streamAudio.add(
      VoiceRemotePcmFrame(
        userId: 'them',
        sourceId: 'stream:guild:guild-1:voice-1:them',
        samples: Int16List.fromList([7, 8]),
      ),
    );
    await _flushEvents();
    expect(playback.frames, isEmpty);

    signaling.emit(const VoiceTransportReadyEvent(_transportSession));
    await _flushEvents();
    await _flushEvents();

    // The stream can become ready before the room connection. The frame is
    // retained until the shared playback service is enabled.
    expect(playback.frames.single.userId, 'them');
    expect(playback.frames.single.samples, [7, 8]);
  });

  test('a session with no voice transport says why it cannot join', () async {
    final media = _FakeVoiceMediaService();
    final controller = VoiceController(media);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.joinBlockedReason, isNotNull);
  });
}

/// One 20 ms microphone frame loud enough to pass the uplink's gate.
final Uint8List _speech = Int16List.fromList(
  List.generate(1920, (index) => (index * 37) % 2000 - 1000),
).buffer.asUint8List();

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
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.disconnected;

  @override
  VoiceTransportSession? currentSession;

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

  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();
  final List<String>? _operations;
  final List<String?> startedInputs = [];
  bool failMicrophone = false;
  bool failMicrophoneToggle = false;
  bool microphoneEnabled = true;
  bool microphoneStopped = false;
  String? selectedOutput;

  void addPcm(Uint8List bytes) => _microphone.add(
    VoicePcmChunk(bytes: bytes, sampleRate: 48000, channels: 2),
  );

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphone.stream;

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
  Future<void> selectAudioOutput(String deviceId) async {
    selectedOutput = deviceId;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (failMicrophoneToggle) throw StateError('device is gone');
    microphoneEnabled = enabled;
    _operations?.add('microphone:$enabled');
  }

  @override
  Future<void> startMicrophone(String? deviceId) async {
    startedInputs.add(deviceId);
    if (failMicrophone) throw StateError('no capture device');
  }

  @override
  Future<void> stopMicrophone() async {
    microphoneStopped = true;
    _operations?.add('microphone:stop');
  }

  @override
  Future<void> dispose() async {
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
  final List<String> removedSources = [];

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
  Future<void> removeSource(String sourceId) async =>
      removedSources.add(sourceId);

  @override
  Future<void> dispose() async => disposed = true;
}
