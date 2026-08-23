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
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

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
    goLive = GoLiveController(
      repositoryProvider: () => repository,
      capture: capture,
    );
    viewer = StreamViewerController(
      repositoryProvider: () => repository,
      decoder: decoder,
    );
    service = DiscordStreamRtcService(
      repositoryProvider: () => repository,
      identityProvider: () => (sessionId: 'session-1', userId: 'me'),
      socketFactoryProvider: () => _StreamSocketFactory((_) {
        final client = _FakeClient(log);
        clients.add(client);
        return client;
      }),
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
  final encoder = _FakeEncoder();
  final clients = <_FakeClient>[];
  final log = <String>[];
  late final VideoCaptureHub capture;
  late final GoLiveController goLive;
  late final StreamViewerController viewer;
  late final DiscordStreamRtcService service;
  late final StreamRouter router;

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

      wiring.encoder.emitFrame();
      await Future<void>.delayed(Duration.zero);

      // Declared before the first packet leaves: Discord drops a packet whose
      // SSRC was never announced. The picture takes two packets, which is what
      // the packetiser does with a keyframe of this size.
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
      expect(wiring.encoder.keyframeRequests, 1);
    },
  );

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
      // Two packets, one picture: the marker survived the mapping.
      expect(wiring.viewer.decodedUnits, 1);
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

/// Carries pictures the same way the production client does, so the video half
/// of a stream connection is testable without a socket. Says what it did into
/// [log], in order, so a test can tell which side of the fork ran first.
final class _FakeClient implements DiscordVoiceClient {
  _FakeClient(this.log);

  final List<String> log;
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<(String, DiscordRtpFrame)> _video =
      StreamController.broadcast();
  final List<DiscordRtpFrame> sentFrames = [];
  final List<({bool enabled, VideoEncoderSettings settings})> announcements =
      [];

  void announce(VoiceSignalingEvent event) => _events.add(event);

  /// Delivers a picture as if it arrived off the wire.
  void emitVideo(String userId, DiscordRtpFrame frame) =>
      _video.add((userId, frame));

  @override
  int? get audioSsrc => null;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets => _video.stream;

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

  /// Recorded group encryptions: whole access units, with the SSRC they were
  /// encrypted for.
  final List<({int ssrc, Uint8List frame})> groupEncryptions = [];

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) {
    groupEncryptions.add((ssrc: ssrc, frame: frame));
    return frame;
  }

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async {
    await _events.close();
    await _video.close();
  }
}

final class _FakeEncoder implements VideoEncoderService {
  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();

  /// Keyframe requests that reached the encoder, which is where a viewer's
  /// picture-loss indication ends up.
  int keyframeRequests = 0;

  /// Emits one small picture, as the capture would.
  void emitFrame() => _frames.add(
    EncodedVideoFrame(
      bytes: _keyframe,
      timestamp: const Duration(milliseconds: 100),
      isKeyframe: true,
    ),
  );

  @override
  bool get isSupported => true;

  @override
  int get displayCount => 1;

  @override
  List<String> get cameraNames => const [];

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start(VideoEncoderSettings settings) async {}

  @override
  Future<void> requestKeyframe() async => keyframeRequests++;

  @override
  Future<void> setPaused({required bool paused}) async {}

  @override
  Future<void> stop() async {}
}

final class _FakeDecoder implements VideoDecoderService {
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  final List<Uint8List> submitted = [];

  Future<void> close() => _frames.close();

  @override
  bool get isSupported => true;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp}) async =>
      submitted.add(accessUnit);

  @override
  Future<void> stop() async {}
}

final class _FakeRepository implements GoLiveRepository {
  final StreamController<GoLiveStream> _updates = StreamController.broadcast();
  final StreamController<GoLiveServer> _servers = StreamController.broadcast();

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
  Future<void> watchStream(GoLiveStreamKey key) async {}

  @override
  Future<void> pingStream(GoLiveStreamKey key) async {}

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async {}

  @override
  Future<void> endStream(GoLiveStreamKey key) async {}
}

/// The socket factory seam, faked on the stream side only.
final class _StreamSocketFactory implements DiscordVoiceSocketFactory {
  _StreamSocketFactory(this._build);

  final DiscordVoiceClient Function(VoiceServerCredentials credentials) _build;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      throw UnsupportedError('the stream plane dials no call sockets');

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) => _build(credentials);
}
