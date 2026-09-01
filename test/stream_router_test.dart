import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/application/stream_router.dart';
import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_service.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/go_live_media_plane.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_audio.dart';

import 'support/fake_video_encoder.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

const _otherKey = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'somebody-else',
);

const _otherServer = GoLiveServer(
  key: _otherKey,
  endpoint: 'stream.discord.gg',
  token: 't',
);

/// One small keyframe: what the encoder produces and a sender packetises.
final Uint8List _keyframe = Uint8List.fromList([
  0,
  0,
  0,
  1,
  0x67,
  0x42,
  0,
  0,
  0,
  1,
  0x65,
  ...List.filled(8, 0xaa),
]);

const _session = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 4242,
  address: '127.0.0.1',
  port: 50000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: <int>[],
  daveProtocolVersion: 0,
);

/// The wiring a stream connection depends on, with every outer edge faked:
/// the repository, the socket and the decode. The router and everything it
/// routes to are the real ones, which is what makes this a test of the fork
/// rather than of a copy of it.
final class _Wiring {
  _Wiring() {
    capture = VideoCaptureHub(encoder: encoder);
    // The share's connection sends in-process here, where the production
    // plane would send from its own isolate.
    plane = InProcessGoLiveMediaPlane(frames: capture.frames);
    goLive = GoLiveController(
      repositoryProvider: () => repository,
      capture: capture,
      media: plane,
    );
    viewer = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () => decoder,
      ownKeyProvider: () => goLive.streamKey,
      onWatchRequested: (key) => service.noteWatch(key),
      onWatchStopped: (key) => unawaited(service.stop(key)),
      // One audio receiver per watched session (ADR-0004).
      audioDecoderFactory: audioCodecs,
    );
    service = DiscordStreamRtcService(
      repositoryProvider: () => repository,
      identityProvider: () => (sessionId: 'session-1', userId: 'me'),
      socketFactoryProvider: _plainSocketFactory,
      sendingSocketFactoryProvider: () =>
          GoLiveMediaSocketFactory(inner: _plainSocketFactory()!, plane: plane),
    )..reconcile();
    router = StreamRouter(
      opened: service.opened,
      goLive: goLive,
      viewer: viewer,
      capture: capture,
    );
  }

  final repository = _FakeRepository();
  final decoder = _FakeDecoder();
  final encoder = FakeVideoEncoder(cameras: const []);
  final audioCodecs = FakeVoiceOpusDecoderFactory();
  final clients = <_FakeClient>[];
  final log = <String>[];
  late final VideoCaptureHub capture;
  late final InProcessGoLiveMediaPlane plane;
  late final GoLiveController goLive;
  late final StreamViewerController viewer;
  late final DiscordStreamRtcService service;
  late final StreamRouter router;

  /// Emits one small picture, as the capture would.
  void emitFrame() => encoder.emit(
    EncodedVideoFrame(
      bytes: _keyframe,
      timestamp: const Duration(milliseconds: 100),
      isKeyframe: true,
    ),
  );

  DiscordVoiceSocketFactory? _plainSocketFactory() => _StreamSocketFactory((_) {
    final client = _FakeClient(log);
    clients.add(client);
    return client;
  });

  Future<void> dispose() async {
    router.dispose();
    goLive.dispose();
    viewer.dispose();
    await service.close();
    await repository.close();
    await decoder.close();
  }
}

/// One small access unit, as the packets a sender would hand the connection.
List<DiscordRtpFrame> _packetizedUnit() => [
  for (final (index, packet) in DiscordH264Packetizer.packetize(
    _keyframe,
  ).indexed)
    DiscordRtpFrame(
      header: DiscordRtpHeader(
        payloadType: DiscordRtpHeader.discordVideoPayloadType,
        sequence: index,
        timestamp: 1,
        ssrc: 99,
        marker: packet.isLast,
      ),
      payload: packet.bytes,
    ),
];

void main() {
  test(
    'a ready stream of ours is declared, then the encoder sends on it',
    () async {
      final wiring = _Wiring();
      addTearDown(wiring.dispose);

      await wiring.goLive.start(channelId: 'voice-1', guildId: 'guild-1');
      // The endpoint arrives long after the button was pressed, and the session
      // it opens is the one this fork decides about.
      wiring.repository.assign(
        const GoLiveServer(
          key: _key,
          endpoint: 'stream.discord.gg',
          token: 't',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(wiring.clients, hasLength(1));
      final client = wiring.clients.single;

      client.announce(const VoiceTransportReadyEvent(_session));
      await Future<void>.delayed(Duration.zero);

      // Declared with what the capture is actually running at, and bound to the
      // SSRC the connection was given.
      expect(client.announcements.single.enabled, isTrue);
      expect(
        client.announcements.single.settings,
        wiring.capture.shareSettings,
      );
      // The encoder's first keyframe left long before the connection was
      // ready, so the sender asks for one as soon as it is bound.
      expect(wiring.encoder.keyframes, 1);

      wiring.emitFrame();
      await Future<void>.delayed(Duration.zero);

      // Declared before the first packet leaves: Discord drops a packet whose
      // SSRC was never announced. The picture takes two packets, which is what
      // the packetiser does with a keyframe of this size; the second is paced
      // out a few milliseconds behind the first.
      expect(wiring.log, ['announce', 'send']);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(wiring.log, ['announce', 'send', 'send']);
      expect(client.sentFrames, isNotEmpty);
      // One above the connection's own SSRC: the announce declared the
      // pictures as audio + 1, and a frame on any other SSRC is dropped —
      // a stream that opens, says it is live, and shows a viewer nothing.
      expect(
        client.sentFrames.every((frame) => frame.header.ssrc == 4243),
        isTrue,
      );
      // The group encryption ran once on the whole picture, before it became
      // two RTP packets: receivers decrypt a frame, not a fragment.
      expect(client.groupEncryptions, hasLength(1));
      expect(client.groupEncryptions.single.ssrc, 4243);
      // The viewer is the other side of the fork, and this was not it.
      expect(wiring.viewer.watching, isNull);

      // A viewer who cannot decode asks for a keyframe, and the request
      // reaches the one capture that could produce one.
      client.announce(const VoiceKeyframeRequestedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(wiring.encoder.keyframes, 2);

      // And a NACK for a packet already sent is answered from the sender's
      // history: the missing sequence goes out again on the rtx SSRC (one
      // above the video's), not the encoder being asked to redraw.
      final before = client.sentFrames.length;
      client.announce(
        const VoiceRetransmitRequestedEvent(ssrc: 4243, sequences: [1]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.sentFrames.length, before + 1);
      expect(client.sentFrames.last.header.ssrc, 4244);
    },
  );

  test('the own stream has one sending and one receiving connection', () async {
    final wiring = _Wiring();
    addTearDown(wiring.dispose);

    await wiring.goLive.start(channelId: 'voice-1', guildId: 'guild-1');
    wiring.repository.assign(
      const GoLiveServer(
        key: _key,
        endpoint: 'stream.discord.gg',
        token: 'send-token',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final sending = wiring.clients.single;
    sending.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);

    // The sender's ready connection triggers the ordinary watch request for
    // the same key. Discord answers it with a second endpoint.
    expect(wiring.repository.watched, [_key]);
    wiring.repository.assign(
      const GoLiveServer(
        key: _key,
        endpoint: 'stream.discord.gg',
        token: 'receive-token',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(wiring.clients, hasLength(2));
    final receiving = wiring.clients.last;
    receiving.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);

    // The role belongs to the connection. The receiving connection has the
    // same key but must not announce or send anything.
    expect(sending.announcements, hasLength(1));
    expect(receiving.announcements, isEmpty);
    expect(receiving.sentFrames, isEmpty);
    expect(wiring.viewer.isWatching(_key), isTrue);
    expect(wiring.viewer.watching, isNull);

    for (final frame in _packetizedUnit()) {
      receiving.emitVideo('me', frame);
    }
    await Future<void>.delayed(Duration.zero);
    expect(wiring.viewer.receivedPacketsFor(_key), 2);
    expect(wiring.viewer.decodedUnitsFor(_key), 1);

    // A different stream can be watched while both own-key connections are
    // alive; it gets its own receiving session and no sender announcement.
    await wiring.viewer.requestWatch(_otherKey);
    wiring.repository.assign(_otherServer);
    await Future<void>.delayed(Duration.zero);
    expect(wiring.clients, hasLength(3));
    final other = wiring.clients.last;
    other.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);
    expect(other.announcements, isEmpty);
    expect(wiring.viewer.isWatching(_key), isTrue);
    expect(wiring.viewer.isWatching(_otherKey), isTrue);
  });

  test('a receiving refusal is logged and kept for the tile', () async {
    final wiring = _Wiring();
    addTearDown(wiring.dispose);

    await wiring.goLive.start(channelId: 'voice-1', guildId: 'guild-1');
    wiring.repository.assign(
      const GoLiveServer(
        key: _key,
        endpoint: 'stream.discord.gg',
        token: 'send-token',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    wiring.clients.single.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);
    wiring.repository.assign(
      const GoLiveServer(
        key: _key,
        endpoint: 'stream.discord.gg',
        token: 'receive-token',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final receiving = wiring.clients.last;
    receiving.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);

    receiving.announce(
      VoiceSignalingStatusEvent(
        VoiceConnectionStatus.failure,
        error: StateError('watch denied'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(wiring.viewer.errorFor(_key), isNotNull);
    expect(wiring.viewer.isOpen(_key), isFalse);
    await wiring.goLive.stop();
  });

  test('a suspended client keeps receiving, and keeps sending', () async {
    final wiring = _Wiring();
    addTearDown(wiring.dispose);

    await wiring.goLive.start(channelId: 'voice-1', guildId: 'guild-1');
    wiring.repository.assign(
      const GoLiveServer(
        key: _key,
        endpoint: 'stream.discord.gg',
        token: 'send-token',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final sending = wiring.clients.single;
    sending.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);
    wiring.repository.assign(
      const GoLiveServer(
        key: _key,
        endpoint: 'stream.discord.gg',
        token: 'receive-token',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final receiving = wiring.clients.last;
    receiving.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);
    expect(wiring.viewer.isWatching(_key), isTrue);
    expect(wiring.decoder.started, 1);

    // The window goes away.
    wiring.viewer.setSuspended(true);
    await Future<void>.delayed(Duration.zero);
    expect(wiring.decoder.stopped, 1);

    // Sending is not the viewer's to suspend: the capture goes on and the
    // connection goes on carrying it.
    final sentBefore = sending.sentFrames.length;
    wiring.emitFrame();
    await Future<void>.delayed(Duration.zero);
    expect(sending.sentFrames.length, greaterThan(sentBefore));
    expect(wiring.goLive.isStreaming, isTrue);

    // A pause is the sender's own act, and it reaches Discord exactly as it
    // did before suspension existed: this client being suspended is not the
    // sender holding pictures back, and neither changes the other.
    await wiring.goLive.setPaused(paused: true);
    await Future<void>.delayed(Duration.zero);
    // The create is followed by an unpause, and then by this pause.
    expect(wiring.repository.pauses, [false, true]);
    expect(wiring.viewer.isSuspended, isTrue);

    // What this client is watching keeps arriving across the connection it
    // already had: no second endpoint is asked for when the window comes
    // back, so the picture does not wait on a handshake.
    for (final frame in _packetizedUnit()) {
      receiving.emitVideo('me', frame);
    }
    await Future<void>.delayed(Duration.zero);
    expect(wiring.viewer.receivedPacketsFor(_key), 2);
    expect(wiring.viewer.decodedUnitsFor(_key), 0);

    wiring.viewer.setSuspended(false);
    await Future<void>.delayed(Duration.zero);
    expect(wiring.decoder.started, 2);
    expect(wiring.repository.watched, [_key]);
    expect(wiring.clients, hasLength(2));

    for (final frame in _packetizedUnit()) {
      receiving.emitVideo('me', frame);
    }
    await Future<void>.delayed(Duration.zero);
    expect(wiring.viewer.receivedPacketsFor(_key), 4);
    expect(wiring.viewer.decodedUnitsFor(_key), 1);
  });

  test(
    'a ready stream of somebody else\'s is attached to the viewer',
    () async {
      final wiring = _Wiring();
      addTearDown(wiring.dispose);

      await wiring.viewer.requestWatch(_otherKey);
      wiring.repository.assign(_otherServer);
      await Future<void>.delayed(Duration.zero);
      final client = wiring.clients.single;

      client.announce(const VoiceTransportReadyEvent(_session));
      await Future<void>.delayed(Duration.zero);

      expect(wiring.viewer.watching, _otherKey);
      // Nobody declared video and nothing was bound: this client is receiving.
      expect(client.announcements, isEmpty);
      expect(client.sentFrames, isEmpty);

      for (final frame in _packetizedUnit()) {
        client.emitVideo('somebody-else', frame);
      }
      await Future<void>.delayed(Duration.zero);

      expect(wiring.viewer.receivedPackets, 2);
      // Two packets, one picture: the marker survived the mapping, and the
      // group decryptor saw the reassembled picture once.
      expect(wiring.viewer.decodedUnits, 1);
      expect(client.groupDecryptions, [_keyframe]);
    },
  );

  test('an unsolicited stream endpoint stays silent', () async {
    final wiring = _Wiring();
    addTearDown(wiring.dispose);

    wiring.repository.assign(_otherServer);
    await Future<void>.delayed(Duration.zero);
    final connection = wiring.clients.single;
    connection.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);

    final heard = <VoiceRemotePcmFrame>[];
    final played = wiring.viewer.audio.listen(heard.add);
    addTearDown(played.cancel);
    connection.emitAudio('somebody-else', [7]);
    await Future<void>.delayed(Duration.zero);

    expect(wiring.viewer.isOpen(_otherKey), isFalse);
    expect(wiring.viewer.isWatching(_otherKey), isFalse);
    expect(wiring.audioCodecs.created, 0);
    expect(heard, isEmpty);
  });

  test('a watched stream\'s sound comes off the stream connection', () async {
    final wiring = _Wiring();
    addTearDown(wiring.dispose);

    await wiring.viewer.requestWatch(_otherKey);
    wiring.repository.assign(_otherServer);
    await Future<void>.delayed(Duration.zero);
    final connection = wiring.clients.single;
    connection.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);
    expect(wiring.viewer.isWatching(_otherKey), isTrue);

    final heard = <VoiceRemotePcmFrame>[];
    final played = wiring.viewer.audio.listen(heard.add);
    addTearDown(played.cancel);
    await Future<void>.delayed(Duration.zero);

    // Audio arrives through the stream connection.
    connection.emitAudio('somebody-else', [7]);
    await Future<void>.delayed(Duration.zero);

    expect(wiring.audioCodecs.created, 1);
    expect(heard.single.userId, 'somebody-else');
    expect(heard.single.samples, [7]);

    // Audio stops with the watched session.
    await wiring.viewer.stop(_otherKey);
    expect(wiring.audioCodecs.disposed, 1);
    connection.emitAudio('somebody-else', [8]);
    await Future<void>.delayed(Duration.zero);
    expect(heard, hasLength(1));
  });

  test(
    'stopping a watched stream closes its connection, not the share',
    () async {
      final wiring = _Wiring();
      addTearDown(wiring.dispose);

      await wiring.goLive.start(channelId: 'voice-1', guildId: 'guild-1');
      wiring.repository.assign(
        const GoLiveServer(
          key: _key,
          endpoint: 'stream.discord.gg',
          token: 's',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final sending = wiring.clients.single;
      sending.announce(const VoiceTransportReadyEvent(_session));
      await Future<void>.delayed(Duration.zero);
      wiring.repository.assign(
        const GoLiveServer(
          key: _key,
          endpoint: 'stream.discord.gg',
          token: 'r',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final receiving = wiring.clients.last;
      receiving.announce(const VoiceTransportReadyEvent(_session));
      await wiring.viewer.requestWatch(_otherKey);
      wiring.repository.assign(_otherServer);
      await Future<void>.delayed(Duration.zero);
      final other = wiring.clients.last;
      other.announce(const VoiceTransportReadyEvent(_session));
      await Future<void>.delayed(Duration.zero);
      expect(wiring.viewer.isWatching(_key), isTrue);
      expect(wiring.viewer.isWatching(_otherKey), isTrue);

      // Closing the self-preview drops the receiving half only (ADR-0001).
      await wiring.viewer.stop(_key);
      await Future<void>.delayed(Duration.zero);
      expect(receiving.closed, isTrue);
      expect(sending.closed, isFalse);
      expect(wiring.service.sessionFor(_key)?.sending, isTrue);
      expect(other.closed, isFalse);

      // A stream somebody else sends goes with its connection: nothing is left
      // decrypting and reordering packets for a picture nobody draws.
      await wiring.viewer.stop(_otherKey);
      await Future<void>.delayed(Duration.zero);
      expect(other.closed, isTrue);
      expect(wiring.service.sessionFor(_otherKey), isNull);
      expect(sending.closed, isFalse);
    },
  );

  test('a disposed router routes nothing', () async {
    final wiring = _Wiring();
    addTearDown(wiring.dispose);

    wiring.router.dispose();
    wiring.repository.assign(_otherServer);
    await Future<void>.delayed(Duration.zero);
    wiring.clients.single.announce(const VoiceTransportReadyEvent(_session));
    await Future<void>.delayed(Duration.zero);

    expect(wiring.clients.single.announcements, isEmpty);
    expect(wiring.viewer.watching, isNull);
  });
}

/// Fake stream client with picture and audio inputs.
final class _FakeClient implements DiscordVoiceClient {
  _FakeClient(this.log);

  final List<String> log;
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<(String, DiscordRtpFrame)> _video =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _audio =
      StreamController.broadcast();
  final List<DiscordRtpFrame> sentFrames = [];
  final List<({bool enabled, VideoEncoderSettings settings})> announcements =
      [];
  bool closed = false;

  void announce(VoiceSignalingEvent event) => _events.add(event);

  /// Delivers a picture as if it arrived off the wire.
  void emitVideo(String userId, DiscordRtpFrame frame) =>
      _video.add((userId, frame));

  /// Delivers an audio frame.
  void emitAudio(String userId, List<int> opus) => _audio.add(
    VoiceRemoteOpusFrame(userId: userId, opus: Uint8List.fromList(opus)),
  );

  @override
  int? get audioSsrc => null;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets => _video.stream;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _audio.stream;

  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    announcements.add((enabled: enabled, settings: settings));
    log.add('announce');
    return true;
  }

  @override
  int sendVideoFrame(DiscordRtpFrame frame) {
    sentFrames.add(frame);
    log.add('send');
    return frame.payload.length;
  }

  @override
  void sendMediaSinkWants({
    Map<int, int> perSsrc = const {},
    int? any,
    Map<int, double> pixelCounts = const {},
  }) {
    log.add('mediaSinkWants');
  }

  @override
  void sendPictureLoss({required int mediaSsrc}) {}

  /// Recorded group encryptions: whole access units, with the SSRC they were
  /// encrypted for.
  final List<({int ssrc, Uint8List frame})> groupEncryptions = [];
  final List<Uint8List> groupDecryptions = [];

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) {
    groupEncryptions.add((ssrc: ssrc, frame: frame));
    return frame;
  }

  @override
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  }) {
    groupDecryptions.add(picture);
    return picture;
  }

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
    await _video.close();
    await _audio.close();
  }
}

final class _FakeDecoder implements VideoDecoderService {
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  final List<Uint8List> submitted = [];

  /// How many times this decoder was opened and shut: a session that is
  /// suspended lets go of its decoder and opens another on the way back.
  int started = 0;
  int stopped = 0;

  Future<void> close() => _frames.close();

  @override
  bool get isSupported => true;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Stream<int> get droppedAccessUnits => const Stream.empty();

  @override
  Future<void> start() async => started++;

  @override
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp}) async =>
      submitted.add(accessUnit);

  @override
  Future<void> stop() async => stopped++;
}

final class _FakeRepository implements GoLiveRepository {
  final StreamController<GoLiveStream> _updates = StreamController.broadcast();
  final StreamController<GoLiveServer> _servers = StreamController.broadcast();
  final List<GoLiveStreamKey> watched = [];

  /// What this client told Discord about holding pictures back, which is the
  /// sender's own act and reaches everybody watching, suspended or not.
  final List<bool> pauses = [];

  void assign(GoLiveServer server) => _servers.add(server);

  Future<void> close() async {
    await _updates.close();
    await _servers.close();
  }

  @override
  Map<String, GoLiveStream> get streams => const {};

  @override
  Stream<GoLiveStream> get updates => _updates.stream;

  @override
  Stream<GoLiveServer> get servers => _servers.stream;

  @override
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) async => guildId == null
      ? GoLiveStreamKey.call(channelId: channelId, userId: 'me')
      : GoLiveStreamKey.guild(
          guildId: guildId,
          channelId: channelId,
          userId: 'me',
        );

  @override
  Future<void> watchStream(GoLiveStreamKey key) async => watched.add(key);

  @override
  Future<void> pingStream(GoLiveStreamKey key) async {}

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async =>
      pauses.add(paused);

  @override
  Future<void> endStream(GoLiveStreamKey key) async {}
}

/// The socket factory seam, faked on the stream side only.
final class _StreamSocketFactory implements DiscordVoiceSocketFactory {
  _StreamSocketFactory(this._build);

  final DiscordVoiceClient Function(VoiceServerCredentials credentials) _build;

  @override
  int get maxDaveProtocolVersion => 0;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      throw UnsupportedError('the stream plane dials no call sockets');

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) => _build(credentials);
}
