part of 'discord_voice_transport_test.dart';

/// Real UDP sockets on the loopback address, with only the voice websocket
/// faked. A socket dies here the way it dies in production: a send hits an OS
/// error, and `dart:io` closes the socket.
void _recoveryCases() {
  group('Voice media socket recovery', () {
    test('a dead socket comes back with an identify, a new socket and '
        'audio in both directions', () async {
      final rig = await _RecoveryRig.start();
      addTearDown(rig.close);
      await rig.client.connect();
      await rig.finishHandshake(rig.lastDial, ssrc: 42);

      rig.killMediaSocket();

      await _until(() => rig.dials.length == 2);
      final dial = rig.lastDial;
      await _until(() => _opcodes(dial).isNotEmpty);
      expect(_opcodes(dial).first, DiscordVoiceGatewayOpcode.identify);

      final cipher = await rig.finishHandshake(dial, ssrc: 43);
      addTearDown(cipher.dispose);
      expect(rig.statuses.last.status, VoiceConnectionStatus.ready);
      expect(rig.server.discoverySources.toSet(), hasLength(2));
      final newPort = rig.server.discoverySources.last;

      rig.client.sendOpusFrame(Uint8List.fromList([1, 2, 3]));
      await _until(() => rig.server.media.isNotEmpty);
      final sent = rig.server.media.single;
      expect(sent.port, newPort);
      final decrypted = cipher.decryptPacket(sent.data);
      expect(decrypted.header.ssrc, 43);
      expect(decrypted.payload, [1, 2, 3]);

      dial.addJson({
        'op': DiscordVoiceGatewayOpcode.speaking,
        'd': {'user_id': 'remote-1', 'ssrc': 77, 'speaking': 1},
      });
      await _flushEvents();
      final heard = rig.client.remoteAudio.first;
      rig.server.sendTo(
        newPort,
        cipher.encryptFrame(
          DiscordRtpFrame(
            header: DiscordRtpHeader(sequence: 1, timestamp: 2, ssrc: 77),
            payload: Uint8List.fromList([6, 7, 8]),
          ),
        ),
      );
      final frame = await heard.timeout(const Duration(seconds: 5));
      expect(frame.userId, 'remote-1');
      expect(frame.opus, [6, 7, 8]);
    });

    test(
      'a socket that dies while a resume waits identifies instead',
      () async {
        final rig = await _RecoveryRig.start();
        addTearDown(rig.close);
        await rig.client.connect();
        await rig.finishHandshake(rig.lastDial, ssrc: 42);

        await rig.lastDial.closeFromServer(1006);
        await _flushEvents();
        rig.killMediaSocket();

        await _until(() => rig.dials.length == 2);
        final dial = rig.lastDial;
        await _until(() => _opcodes(dial).isNotEmpty);
        expect(_opcodes(dial).first, DiscordVoiceGatewayOpcode.identify);
      },
    );

    test('a session waiting for new credentials does not redial when its '
        'socket dies', () async {
      final rig = await _RecoveryRig.start();
      addTearDown(rig.close);
      await rig.client.connect();
      await rig.finishHandshake(rig.lastDial, ssrc: 42);

      await rig.lastDial.closeFromServer(4014);
      await _flushEvents();
      rig.killMediaSocket();
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(rig.dials, hasLength(1));
    });
  });

  group('Voice UDP discovery recovery', () {
    test('one dropped datagram still completes discovery', () async {
      final server = await _LoopbackMediaServer.start();
      addTearDown(server.close);
      server.discoveriesToDrop = 1;
      final transport = IoDiscordVoiceUdpTransport(
        discoveryResend: const Duration(milliseconds: 50),
      );
      addTearDown(transport.close);

      final found = await transport.discover(
        host: '127.0.0.1',
        port: server.port,
        ssrc: 42,
      );

      expect(server.discoverySources, hasLength(2));
      expect(found.address, '127.0.0.1');
      expect(found.port, server.discoverySources.last);
    });

    test('a late failure from an old discovery does not end the newer '
        'connection', () async {
      final rig = await _RecoveryRig.start();
      addTearDown(rig.close);
      rig.server.answersDiscovery = false;
      await rig.client.connect();

      rig.lastDial.addJson(_voiceReadyFrame(rig.server.port, ssrc: 42));
      await _until(() => rig.server.discoverySources.isNotEmpty);
      await rig.lastDial.closeFromServer(1006);
      await _until(() => rig.dials.length == 2);
      await _until(() => _opcodes(rig.lastDial).isNotEmpty);

      // The newer connection's discovery closes the old socket, and that
      // fails the old discovery while this one is running.
      rig.server.answersDiscovery = true;
      await rig.finishHandshake(rig.lastDial, ssrc: 43);

      expect(rig.statuses.last.status, VoiceConnectionStatus.ready);
      expect(
        rig.statuses.map((event) => event.status),
        isNot(contains(VoiceConnectionStatus.failure)),
      );
    });

    test('no answer at all ends in failure after the window', () async {
      final rig = await _RecoveryRig.start(
        discoveryWindow: const Duration(milliseconds: 300),
        discoveryResend: const Duration(milliseconds: 50),
      );
      addTearDown(rig.close);
      rig.server.answersDiscovery = false;
      await rig.client.connect();

      rig.lastDial.addJson(_voiceReadyFrame(rig.server.port, ssrc: 42));
      await _until(
        () => rig.statuses.last.status == VoiceConnectionStatus.failure,
      );

      expect(rig.statuses.last.error, isA<TimeoutException>());
      expect(rig.server.discoverySources.length, greaterThan(1));
    });

    test('a socket that dies during discovery ends in failure', () async {
      final rig = await _RecoveryRig.start();
      addTearDown(rig.close);
      await rig.client.connect();

      // Without the broadcast option, a send to this address is an OS error.
      rig.lastDial.addJson(
        _voiceReadyFrame(rig.server.port, ssrc: 42, ip: '255.255.255.255'),
      );
      await _until(
        () => rig.statuses.last.status == VoiceConnectionStatus.failure,
      );

      expect(rig.statuses.last.error, isA<SocketException>());
      expect(rig.dials, hasLength(1));
    });

    test('a newer discovery replaces one still starting', () async {
      final server = await _LoopbackMediaServer.start();
      addTearDown(server.close);
      final transport = IoDiscordVoiceUdpTransport();
      addTearDown(transport.close);

      final older = transport.discover(
        host: '127.0.0.1',
        port: server.port,
        ssrc: 42,
      );
      final newer = transport.discover(
        host: '127.0.0.1',
        port: server.port,
        ssrc: 42,
      );

      await expectLater(older, throwsA(isA<SocketException>()));
      await newer;
      expect(server.discoverySources.toSet(), hasLength(1));
    });
  });
}

const _recoveryMode = 'aead_aes256_gcm_rtpsize';

Map<String, Object?> _voiceReadyFrame(
  int port, {
  required int ssrc,
  String ip = '127.0.0.1',
}) => {
  'op': DiscordVoiceGatewayOpcode.ready,
  'd': {
    'ssrc': ssrc,
    'ip': ip,
    'port': port,
    'modes': [_recoveryMode],
  },
};

Iterable<int?> _opcodes(_FakeVoiceWebSocket socket) => socket.sent
    .whereType<String>()
    .map((frame) => (jsonDecode(frame) as Map)['op'] as int?);

/// Waits on real sockets, which no fake clock can move.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The wait timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A gateway client over a real UDP transport, a loopback media server, and a
/// new fake websocket for each dial.
final class _RecoveryRig implements DiscordVoiceSocketConnector {
  _RecoveryRig._(this.server, this.udp) {
    client = DiscordVoiceGatewayClient(
      credentials: _credentials,
      maxDaveProtocolVersion: 0,
      socketConnector: this,
      udpTransport: udp,
    );
    _subscription = client.events.listen((event) {
      if (event is VoiceSignalingStatusEvent) statuses.add(event);
    });
  }

  static Future<_RecoveryRig> start({
    Duration discoveryWindow = const Duration(seconds: 5),
    Duration discoveryResend = const Duration(seconds: 1),
  }) async => _RecoveryRig._(
    await _LoopbackMediaServer.start(),
    IoDiscordVoiceUdpTransport(
      discoveryWindow: discoveryWindow,
      discoveryResend: discoveryResend,
    ),
  );

  final _LoopbackMediaServer server;
  final IoDiscordVoiceUdpTransport udp;
  late final DiscordVoiceGatewayClient client;
  late final StreamSubscription<VoiceSignalingEvent> _subscription;
  final List<_FakeVoiceWebSocket> dials = [];
  final List<VoiceSignalingStatusEvent> statuses = [];
  int _nextKeyByte = 0;

  _FakeVoiceWebSocket get lastDial => dials.last;

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async {
    final socket = _FakeVoiceWebSocket();
    dials.add(socket);
    return socket;
  }

  /// Too large for any datagram, so the OS refuses it.
  void killMediaSocket() => udp.send(Uint8List(70000));

  /// Runs READY through to the session description on [dial], as Discord
  /// would, and returns a cipher that holds the same key as the client.
  ///
  /// The client must be listening to [dial] already. A dial is in [dials]
  /// before that, and the fake drops a frame that nobody listens to. Wait for
  /// the client's first frame, the one Discord answers on the real socket.
  Future<DiscordVoiceTransportCipher> finishHandshake(
    _FakeVoiceWebSocket dial, {
    required int ssrc,
  }) async {
    dial.addJson(_voiceReadyFrame(server.port, ssrc: ssrc));
    await _until(
      () => _opcodes(dial).contains(DiscordVoiceGatewayOpcode.selectProtocol),
    );
    final keyByte = _nextKeyByte++;
    final secretKey = List<int>.generate(32, (index) => index + keyByte);
    dial.addJson({
      'op': DiscordVoiceGatewayOpcode.sessionDescription,
      'd': {
        'mode': _recoveryMode,
        'secret_key': secretKey,
        'dave_protocol_version': 0,
      },
    });
    await _flushEvents();
    return DiscordVoiceTransportCipher(
      mode: _recoveryMode,
      secretKey: secretKey,
    );
  }

  Future<void> close() async {
    await _subscription.cancel();
    await client.close();
    server.close();
  }
}

/// Answers discovery the way Discord does and keeps every other datagram.
final class _LoopbackMediaServer {
  _LoopbackMediaServer._(this._socket) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram != null) _accept(datagram);
    });
  }

  static Future<_LoopbackMediaServer> start() async => _LoopbackMediaServer._(
    await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final RawDatagramSocket _socket;

  /// The client port of each discovery request that arrived.
  final List<int> discoverySources = [];
  final List<Datagram> media = [];
  int discoveriesToDrop = 0;
  bool answersDiscovery = true;

  int get port => _socket.port;

  void sendTo(int clientPort, Uint8List packet) =>
      _socket.send(packet, InternetAddress.loopbackIPv4, clientPort);

  void _accept(Datagram datagram) {
    final packet = datagram.data;
    if (packet.length != DiscordVoiceDiscoveryPacket.size) {
      // The keepalives are eight bytes and carry no audio.
      if (packet.length > 8) media.add(datagram);
      return;
    }
    discoverySources.add(datagram.port);
    if (!answersDiscovery) return;
    if (discoveriesToDrop > 0) {
      discoveriesToDrop--;
      return;
    }
    sendTo(datagram.port, _discoveryAnswer(datagram.port));
  }

  static Uint8List _discoveryAnswer(int clientPort) {
    final packet = Uint8List(DiscordVoiceDiscoveryPacket.size);
    ByteData.sublistView(packet)
      ..setUint16(0, 2, Endian.big)
      ..setUint16(2, 70, Endian.big)
      ..setUint16(72, clientPort, Endian.big);
    packet.setRange(8, 17, ascii.encode('127.0.0.1'));
    return packet;
  }

  void close() => _socket.close();
}
