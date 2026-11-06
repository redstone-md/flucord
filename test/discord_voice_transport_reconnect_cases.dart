part of 'discord_voice_transport_test.dart';

/// The voice socket's redial schedule, on a fake clock: how long it waits, when
/// it gives up, and that a connection that came back starts over.
void _reconnectCases() {
  group('Voice socket redial', () {
    test('an unreachable voice server is dialled after 2, 4, 8, 16 and 30 '
        'seconds, then the cap', () {
      fakeAsync((async) {
        final server = _FlakyVoiceServer(async);
        final rig = _RedialRig(server);

        unawaited(rig.client.connect());
        async.elapse(const Duration(seconds: 61));

        expect(server.dialledAt, const [
          Duration.zero,
          Duration(seconds: 2),
          Duration(seconds: 6),
          Duration(seconds: 14),
          Duration(seconds: 30),
          Duration(seconds: 60),
        ]);
        rig.close();
        async.flushMicrotasks();
      });
    });

    test('gives up after the last attempt and says the connection failed', () {
      fakeAsync((async) {
        final server = _FlakyVoiceServer(async);
        final rig = _RedialRig(server);

        unawaited(rig.client.connect());
        async.elapse(const Duration(minutes: 10));

        // The first dial, and one for each of the six attempts.
        expect(server.dialledAt, hasLength(7));
        expect(rig.statuses.last.status, VoiceConnectionStatus.failure);
        expect(rig.statuses.last.error.toString(), contains('6 attempts'));
        rig.close();
        async.flushMicrotasks();
      });
    });

    test('a successful identify gives the next outage every attempt again', () {
      fakeAsync((async) {
        final server = _FlakyVoiceServer(async);
        final rig = _RedialRig(server);

        unawaited(rig.client.connect());
        async.elapse(const Duration(seconds: 6));
        server.reachable = true;
        async.elapse(const Duration(seconds: 8));
        expect(server.dialledAt.last, const Duration(seconds: 14));
        rig.finishHandshake(async);
        expect(rig.statuses.last.status, VoiceConnectionStatus.ready);

        server.reachable = false;
        rig.dropSocket(async);
        async.elapse(const Duration(seconds: 2));

        expect(server.dialledAt.last, const Duration(seconds: 16));
        rig.close();
        async.flushMicrotasks();
      });
    });

    test('a successful resume gives the next outage every attempt again', () {
      fakeAsync((async) {
        final server = _FlakyVoiceServer(async)..reachable = true;
        final rig = _RedialRig(server);
        unawaited(rig.client.connect());
        async.flushMicrotasks();
        rig.finishHandshake(async);

        server.reachable = false;
        rig.dropSocket(async);
        async.elapse(const Duration(seconds: 6));
        server.reachable = true;
        async.elapse(const Duration(seconds: 8));
        expect(server.dialledAt.last, const Duration(seconds: 14));
        expect(
          _opcodes(server.sockets.last).first,
          DiscordVoiceGatewayOpcode.resume,
        );
        server.sockets.last.addJson({
          'op': DiscordVoiceGatewayOpcode.resumed,
          'd': null,
        });
        async.flushMicrotasks();
        expect(rig.statuses.last.status, VoiceConnectionStatus.ready);

        server.reachable = false;
        rig.dropSocket(async);
        async.elapse(const Duration(seconds: 2));

        expect(server.dialledAt.last, const Duration(seconds: 16));
        rig.close();
        async.flushMicrotasks();
      });
    });
  });
}

/// A voice server that refuses every dial until it is [reachable], and opens a
/// new fake socket for each one after that.
final class _FlakyVoiceServer implements DiscordVoiceSocketConnector {
  _FlakyVoiceServer(this._async);

  final FakeAsync _async;
  bool reachable = false;

  /// When each dial came, on the fake clock.
  final List<Duration> dialledAt = [];
  final List<FakeVoiceWebSocket> sockets = [];

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async {
    dialledAt.add(_async.elapsed);
    if (!reachable) throw const SocketException('Connection refused');
    final socket = FakeVoiceWebSocket();
    sockets.add(socket);
    return socket;
  }
}

/// A gateway client whose waits are exact: jitter takes nothing off.
final class _RedialRig {
  _RedialRig(this.server) {
    client = DiscordVoiceGatewayClient(
      credentials: _credentials,
      maxDaveProtocolVersion: 0,
      socketConnector: server,
      udpTransport: _FakeVoiceUdpTransport(),
      reconnectBackoff: VoiceReconnectBackoff(jitter: () => 0),
      now: () => Duration.zero,
    );
    _subscription = client.events.listen((event) {
      if (event is VoiceSignalingStatusEvent) statuses.add(event);
    });
  }

  final _FlakyVoiceServer server;
  late final DiscordVoiceGatewayClient client;
  late final StreamSubscription<VoiceSignalingEvent> _subscription;
  final List<VoiceSignalingStatusEvent> statuses = [];

  /// READY through to the session description on the newest socket.
  void finishHandshake(FakeAsync async) {
    server.sockets.last.addJson({
      'op': DiscordVoiceGatewayOpcode.ready,
      'd': {
        'ssrc': 42,
        'ip': '198.51.100.4',
        'port': 50001,
        'modes': ['aead_aes256_gcm_rtpsize'],
      },
    });
    async.flushMicrotasks();
    server.sockets.last.addJson({
      'op': DiscordVoiceGatewayOpcode.sessionDescription,
      'd': {
        'mode': 'aead_aes256_gcm_rtpsize',
        'secret_key': List<int>.generate(32, (index) => index),
        'dave_protocol_version': 0,
      },
    });
    async.flushMicrotasks();
  }

  /// The socket closes the way a network drop closes it.
  void dropSocket(FakeAsync async) {
    unawaited(server.sockets.last.closeFromServer(1006));
    async.flushMicrotasks();
  }

  void close() {
    unawaited(_subscription.cancel());
    unawaited(client.close());
  }
}
