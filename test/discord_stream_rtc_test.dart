import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_service.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_session.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'streamer',
);

void main() {
  group('one stream connection', () {
    test('dials the endpoint Discord answered with', () async {
      late VoiceServerCredentials seen;
      final client = _FakeClient();
      final session = DiscordStreamRtcSession(
        key: _key,
        credentials: _credentials,
        socketFactory: _StreamSocketFactory((credentials) {
          seen = credentials;
          return client;
        }),
      );
      addTearDown(session.close);

      await session.connect();

      // The stream's own endpoint and token, not the call's: Discord routes
      // Go Live over a second connection and sends nothing down the first.
      expect(seen.endpoint, 'stream.discord.gg');
      expect(seen.token, 'stream-token');
      // The guild identifies the connection, the same way voice does.
      expect(seen.serverId, 'guild-1');
      expect(client.connects, 1);
    });

    test('a second connect on a live session does not dial twice', () async {
      final client = _FakeClient();
      final session = DiscordStreamRtcSession(
        key: _key,
        credentials: _credentials,
        socketFactory: _StreamSocketFactory((_) => client),
      );
      addTearDown(session.close);

      await session.connect();
      await session.connect();

      expect(client.connects, 1);
    });

    test('remembers the SSRC the connection was given', () async {
      final client = _FakeClient();
      final session = DiscordStreamRtcSession(
        key: _key,
        credentials: _credentials,
        socketFactory: _StreamSocketFactory((_) => client),
      );
      addTearDown(session.close);
      await session.connect();

      expect(session.ssrc, isNull);
      client.announce(const VoiceTransportReadyEvent(_session));
      await Future<void>.delayed(Duration.zero);

      expect(session.ssrc, 4242);
    });

    test(
      'a viewer subscribes to the media server through Media Sink Wants on ready',
      () async {
        final client = _FakeClient();
        final session = DiscordStreamRtcSession(
          key: _key,
          credentials: _credentials,
          socketFactory: _StreamSocketFactory((_) => client),
        );
        addTearDown(session.close);
        await session.connect();

        // Nothing before the connection is ready: the media server is not
        // listening.
        expect(client.mediaSinkWants, isEmpty);
        client.announce(const VoiceTransportReadyEvent(_session));
        await Future<void>.delayed(Duration.zero);

        expect(client.mediaSinkWants, hasLength(1));
        expect(client.mediaSinkWants.single.any, 100);
      },
    );

    test(
      'a viewer asks for the sender by name once its video SSRC is known',
      () async {
        final client = _FakeClient();
        final session = DiscordStreamRtcSession(
          key: _key,
          credentials: _credentials,
          socketFactory: _StreamSocketFactory((_) => client),
        );
        addTearDown(session.close);
        await session.connect();
        client.announce(const VoiceTransportReadyEvent(_session));
        await Future<void>.delayed(Duration.zero);
        expect(client.mediaSinkWants, hasLength(1));

        // The ready ask could only say "any". A picture is what names the
        // sender's video SSRC, and from then on the ask carries it with the
        // pixel count of the view behind it.
        client.emitVideo('somebody-else', _frame);
        await Future<void>.delayed(Duration.zero);

        expect(client.mediaSinkWants, hasLength(2));
        final ask = client.mediaSinkWants.last;
        expect(ask.perSsrc, {1: 100});
        expect(ask.any, 100);
        expect(ask.pixelCounts.keys.single, 1);
        expect(ask.pixelCounts.values.single, 1920 * 1080.0);

        // Packets keep coming sixty to the second; the ask is not one of
        // them.
        client.emitVideo('somebody-else', _frame);
        client.emitVideo('somebody-else', _frame);
        await Future<void>.delayed(Duration.zero);
        expect(client.mediaSinkWants, hasLength(2));

        // A sender that comes back on a new SSRC is asked for again.
        final reconnected = DiscordRtpFrame(
          header: DiscordRtpHeader(
            payloadType: DiscordRtpHeader.discordVideoPayloadType,
            sequence: 2,
            timestamp: 2,
            ssrc: 2,
          ),
          payload: Uint8List.fromList(const [4, 5]),
        );
        client.emitVideo('somebody-else', reconnected);
        await Future<void>.delayed(Duration.zero);

        expect(client.mediaSinkWants, hasLength(3));
        expect(client.mediaSinkWants.last.perSsrc, {2: 100});
      },
    );

    test('forwards the pictures arriving on the connection', () async {
      final client = _FakeClient();
      final session = DiscordStreamRtcSession(
        key: _key,
        credentials: _credentials,
        socketFactory: _StreamSocketFactory((_) => client),
      );
      addTearDown(session.close);
      await session.connect();

      final received = <(String, DiscordRtpFrame)>[];
      final subscription = session.video.listen(received.add);
      addTearDown(subscription.cancel);

      client.emitVideo('somebody-else', _frame);
      await Future<void>.delayed(Duration.zero);

      expect(received, [('somebody-else', _frame)]);
    });

    test('forwards the sound arriving on the connection', () async {
      final client = _FakeClient();
      final session = DiscordStreamRtcSession(
        key: _key,
        credentials: _credentials,
        socketFactory: _StreamSocketFactory((_) => client),
      );
      addTearDown(session.close);
      await session.connect();

      final heard = <VoiceRemoteOpusFrame>[];
      final subscription = session.audio.listen(heard.add);
      addTearDown(subscription.cancel);

      client.emitAudio('sender', [7, 8]);
      await Future<void>.delayed(Duration.zero);

      // Audio arrives through the stream connection (ADR-0004).
      expect(heard.single.userId, 'sender');
      expect(heard.single.opus, [7, 8]);
    });
  });

  group('the connections a session holds', () {
    test('opens one per stream Discord hands an endpoint for', () async {
      final repository = _FakeRepository();
      final clients = <_FakeClient>[];
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        socketFactoryProvider: () => _StreamSocketFactory((_) {
          final client = _FakeClient();
          clients.add(client);
          return client;
        }),
      );
      addTearDown(service.close);
      service.reconcile();

      repository.announceServer(
        const GoLiveServer(
          key: _key,
          endpoint: 'stream.discord.gg',
          token: 'stream-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(clients, hasLength(1));
      expect(service.sessionFor(_key), isNotNull);
    });

    test(
      'identifies with the RTC server Discord named for the stream',
      () async {
        final repository = _FakeRepository();
        late VoiceServerCredentials seen;
        final service = DiscordStreamRtcService(
          repositoryProvider: () => repository,
          identityProvider: () => (sessionId: 'session-1', userId: 'me'),
          socketFactoryProvider: () => _StreamSocketFactory((credentials) {
            seen = credentials;
            return _FakeClient();
          }),
        );
        addTearDown(service.close);
        service.reconcile();

        repository.announceServer(
          const GoLiveServer(
            key: _key,
            endpoint: 'stream.discord.gg',
            token: 'stream-token',
            rtcServerId: 'rtc-77',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Not the guild. Discord gives a stream its own RTC server, and a
        // connection identifying with the guild is closed with
        // `sessionInvalid`.
        expect(seen.serverId, 'rtc-77');
      },
    );

    test('falls back to the guild when no RTC server was named', () async {
      final repository = _FakeRepository();
      late VoiceServerCredentials seen;
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        socketFactoryProvider: () => _StreamSocketFactory((credentials) {
          seen = credentials;
          return _FakeClient();
        }),
      );
      addTearDown(service.close);
      service.reconcile();

      repository.announceServer(
        const GoLiveServer(
          key: _key,
          endpoint: 'stream.discord.gg',
          token: 'stream-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen.serverId, 'guild-1');
    });

    test('an endpoint with no session behind it is dropped', () async {
      final repository = _FakeRepository();
      var made = 0;
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        // Before the account's voice session exists there is nothing to
        // identify with, and Discord reissues the endpoint on the next ask.
        identityProvider: () => null,
        socketFactoryProvider: () => _StreamSocketFactory((_) {
          made++;
          return _FakeClient();
        }),
      );
      addTearDown(service.close);
      service.reconcile();

      repository.announceServer(
        const GoLiveServer(
          key: _key,
          endpoint: 'stream.discord.gg',
          token: 'stream-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(made, 0);
      expect(service.sessionFor(_key), isNull);
    });

    test('a replaced endpoint closes the connection it replaces', () async {
      final repository = _FakeRepository();
      final clients = <_FakeClient>[];
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        socketFactoryProvider: () => _StreamSocketFactory((_) {
          final client = _FakeClient();
          clients.add(client);
          return client;
        }),
      );
      addTearDown(service.close);
      service.reconcile();

      for (final token in ['first', 'second']) {
        repository.announceServer(
          GoLiveServer(key: _key, endpoint: 'stream.discord.gg', token: token),
        );
        await Future<void>.delayed(Duration.zero);
      }

      // Two sockets for one stream would both be sending.
      expect(clients, hasLength(2));
      expect(clients.first.closed, isTrue);
      expect(clients.last.closed, isFalse);
    });

    test("an own endpoint with no watch pending is the sender's", () async {
      final repository = _FakeRepository();
      var made = 0;
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        socketFactoryProvider: () => _StreamSocketFactory((_) {
          made++;
          return _FakeClient();
        }),
      );
      addTearDown(service.close);
      service.reconcile();
      final endpoints = <DiscordSenderEndpoint>[];
      service.senderEndpoints.listen(endpoints.add);

      repository.announceServer(
        const GoLiveServer(
          key: _ownKey,
          endpoint: 'stream.discord.gg',
          token: 'stream-token',
          rtcServerId: 'rtc-77',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Handed out to be sent on, with the credentials to dial it; nothing
      // is opened here (ADR-0001).
      expect(made, 0);
      expect(service.sessionFor(_ownKey), isNull);
      expect(endpoints.single.key, _ownKey);
      expect(endpoints.single.credentials.serverId, 'rtc-77');
      expect(endpoints.single.credentials.token, 'stream-token');
    });

    test('an own endpoint answering a watch is watched', () async {
      final repository = _FakeRepository();
      final clients = <_FakeClient>[];
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        socketFactoryProvider: () => _StreamSocketFactory((_) {
          final client = _FakeClient();
          clients.add(client);
          return client;
        }),
      );
      addTearDown(service.close);
      service.reconcile();
      final endpoints = <DiscordSenderEndpoint>[];
      service.senderEndpoints.listen(endpoints.add);

      // The self-preview's ask, noted before Discord answers it.
      service.noteWatch(_ownKey);
      repository.announceServer(
        const GoLiveServer(
          key: _ownKey,
          endpoint: 'stream.discord.gg',
          token: 'watch-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(endpoints, isEmpty);
      expect(clients, hasLength(1));
      expect(service.sessionFor(_ownKey), isNotNull);

      // The watch is consumed: the next own endpoint is the sender's again.
      repository.announceServer(
        const GoLiveServer(
          key: _ownKey,
          endpoint: 'stream.discord.gg',
          token: 'send-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(endpoints, hasLength(1));
      expect(clients, hasLength(1));
    });

    test('a stream that ends closes its connection', () async {
      final repository = _FakeRepository();
      final clients = <_FakeClient>[];
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        socketFactoryProvider: () => _StreamSocketFactory((_) {
          final client = _FakeClient();
          clients.add(client);
          return client;
        }),
      );
      addTearDown(service.close);
      service.reconcile();

      repository.announceServer(
        const GoLiveServer(
          key: _key,
          endpoint: 'stream.discord.gg',
          token: 'stream-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.sessionFor(_key), isNotNull);

      // Both a local end and a STREAM_DELETE dispatch publish the stream's
      // final state after removing it from the repository.
      repository.end(_key);
      await Future<void>.delayed(Duration.zero);

      expect(service.sessionFor(_key), isNull);
      expect(clients.single.closed, isTrue);
    });

    test('stopping one leaves the others alone', () async {
      final repository = _FakeRepository();
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        socketFactoryProvider: () => _StreamSocketFactory((_) => _FakeClient()),
      );
      addTearDown(service.close);
      service.reconcile();
      const other = GoLiveStreamKey.guild(
        guildId: 'guild-1',
        channelId: 'voice-1',
        userId: 'somebody-else',
      );
      for (final key in [_key, other]) {
        repository.announceServer(
          GoLiveServer(key: key, endpoint: 'stream.discord.gg', token: 'token'),
        );
      }
      await Future<void>.delayed(Duration.zero);

      await service.stop(_key);

      expect(service.sessionFor(_key), isNull);
      expect(service.sessionFor(other), isNotNull);
      expect(service.videoFor(_key), isNotNull);
    });

    test('rebinding to the same transport does not resubscribe', () {
      final repository = _FakeRepository();
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        socketFactoryProvider: () => _StreamSocketFactory((_) => _FakeClient()),
      );
      addTearDown(service.close);

      expect(service.reconcile(), isTrue);
      expect(service.reconcile(), isTrue);
      expect(repository.serverListeners, 1);
    });
  });
}

const _ownKey = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

const _credentials = VoiceServerCredentials(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
  sessionId: 'session-1',
  token: 'stream-token',
  endpoint: 'stream.discord.gg',
);

const _session = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 4242,
  address: '127.0.0.1',
  port: 50000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: <int>[],
  daveProtocolVersion: 0,
);

final _frame = DiscordRtpFrame(
  header: DiscordRtpHeader(
    payloadType: DiscordRtpHeader.discordVideoPayloadType,
    sequence: 1,
    timestamp: 1,
    ssrc: 1,
  ),
  payload: Uint8List.fromList(const [1, 2, 3]),
);

/// Fake stream client with picture and audio inputs.
final class _FakeClient implements DiscordVoiceClient {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<(String, DiscordRtpFrame)> _video =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _audio =
      StreamController.broadcast();
  final List<DiscordRtpFrame> sentFrames = [];
  final List<({bool enabled, VideoEncoderSettings settings})> announcements =
      [];
  final List<({Map<int, int> perSsrc, int? any, Map<int, double> pixelCounts})>
  mediaSinkWants = [];
  int connects = 0;
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
    return true;
  }

  @override
  int sendVideoFrame(DiscordRtpFrame frame) {
    sentFrames.add(frame);
    return frame.payload.length;
  }

  @override
  void sendMediaSinkWants({
    Map<int, int> perSsrc = const {},
    int? any,
    Map<int, double> pixelCounts = const {},
  }) {
    mediaSinkWants.add((perSsrc: perSsrc, any: any, pixelCounts: pixelCounts));
  }

  @override
  void sendPictureLoss({required int mediaSsrc}) {}

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) => frame;

  @override
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  }) => picture;

  @override
  Future<void> connect() async => connects++;

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
    await _video.close();
  }
}

final class _FakeRepository implements GoLiveRepository {
  final StreamController<GoLiveServer> _servers = StreamController.broadcast();
  final StreamController<GoLiveStream> _updates = StreamController.broadcast();
  final Map<String, GoLiveStream> _streams = {};
  int serverListeners = 0;

  void announceServer(GoLiveServer server) {
    _streams.putIfAbsent(server.key.value, () => GoLiveStream(key: server.key));
    _servers.add(server);
  }

  /// Ends a stream the way the real repository does: removed first, the
  /// final state published after.
  void end(GoLiveStreamKey key) {
    final removed = _streams.remove(key.value);
    if (removed != null) _updates.add(removed.copyWith(viewerIds: const []));
  }

  @override
  Map<String, GoLiveStream> get streams => _streams;

  @override
  Stream<GoLiveStream> get updates => _updates.stream;

  @override
  Stream<GoLiveServer> get servers {
    serverListeners++;
    return _servers.stream;
  }

  @override
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) async => _key;

  @override
  Future<void> watchStream(GoLiveStreamKey key) async {}

  @override
  Future<void> pingStream(GoLiveStreamKey key) async {}

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async {}

  @override
  Future<void> endStream(GoLiveStreamKey key) async {}
}

/// The socket factory seam, faked on the stream side only: hands back the
/// client the test chose and shows what credentials were dialled with.
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
