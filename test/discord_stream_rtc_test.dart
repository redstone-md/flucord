import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_service.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_session.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
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
        clientFactory: (credentials) {
          seen = credentials;
          return client;
        },
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
        clientFactory: (_) => client,
      );
      addTearDown(session.close);

      await session.connect();
      await session.connect();

      expect(client.connects, 1);
    });

    test('sending before the connection is up says so', () async {
      final session = DiscordStreamRtcSession(
        key: _key,
        credentials: _credentials,
        clientFactory: (_) => _FakeClient(),
      );
      addTearDown(session.close);

      // Silently dropping the frame would look like a stream that opened and
      // showed a black rectangle.
      expect(
        () => session.sendVideoFrame(_frame),
        throwsA(isA<StateError>()),
      );
      expect(session.announceVideo(enabled: true), isFalse);
    });

    test('remembers the SSRC the connection was given', () async {
      final client = _FakeClient();
      final session = DiscordStreamRtcSession(
        key: _key,
        credentials: _credentials,
        clientFactory: (_) => client,
      );
      addTearDown(session.close);
      await session.connect();

      expect(session.ssrc, isNull);
      client.announce(const VoiceTransportReadyEvent(_session));
      await Future<void>.delayed(Duration.zero);

      expect(session.ssrc, 4242);
    });
  });

  group('the connections a session holds', () {
    test('opens one per stream Discord hands an endpoint for', () async {
      final repository = _FakeRepository();
      final clients = <_FakeClient>[];
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        clientFactory: (_) {
          final client = _FakeClient();
          clients.add(client);
          return client;
        },
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

    test('an endpoint with no session behind it is dropped', () async {
      final repository = _FakeRepository();
      var made = 0;
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        // Before the account's voice session exists there is nothing to
        // identify with, and Discord reissues the endpoint on the next ask.
        identityProvider: () => null,
        clientFactory: (_) {
          made++;
          return _FakeClient();
        },
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
        clientFactory: (_) {
          final client = _FakeClient();
          clients.add(client);
          return client;
        },
      );
      addTearDown(service.close);
      service.reconcile();

      for (final token in ['first', 'second']) {
        repository.announceServer(
          GoLiveServer(
            key: _key,
            endpoint: 'stream.discord.gg',
            token: token,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      // Two sockets for one stream would both be sending.
      expect(clients, hasLength(2));
      expect(clients.first.closed, isTrue);
      expect(clients.last.closed, isFalse);
    });

    test('stopping one leaves the others alone', () async {
      final repository = _FakeRepository();
      final service = DiscordStreamRtcService(
        repositoryProvider: () => repository,
        identityProvider: () => (sessionId: 'session-1', userId: 'me'),
        clientFactory: (_) => _FakeClient(),
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
          GoLiveServer(
            key: key,
            endpoint: 'stream.discord.gg',
            token: 'token',
          ),
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
        clientFactory: (_) => _FakeClient(),
      );
      addTearDown(service.close);

      expect(service.reconcile(), isTrue);
      expect(service.reconcile(), isTrue);
      expect(repository.serverListeners, 1);
    });
  });
}

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
    payloadType: 101,
    sequence: 1,
    timestamp: 1,
    ssrc: 1,
  ),
  payload: Uint8List.fromList(const [1, 2, 3]),
);

final class _FakeClient implements DiscordVoiceClient {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  int connects = 0;
  bool closed = false;

  void announce(VoiceSignalingEvent event) => _events.add(event);

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  @override
  Future<void> connect() async => connects++;

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}

final class _FakeRepository implements GoLiveRepository {
  final StreamController<GoLiveServer> _servers = StreamController.broadcast();
  final StreamController<GoLiveStream> _updates = StreamController.broadcast();
  int serverListeners = 0;

  void announceServer(GoLiveServer server) => _servers.add(server);

  @override
  Map<String, GoLiveStream> get streams => const {};

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
