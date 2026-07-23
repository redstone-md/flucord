import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_voice_session_assembler.dart';
import 'package:flucord/src/data/discord/discord_voice_udp_transport.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_dave.dart';

void main() {
  group('Discord voice session signaling', () {
    test('uses the documented main Gateway opcode 4 payload', () {
      final protocol = DiscordGatewayProtocol(token: 'token', intents: 1);

      expect(
        protocol.voiceStateUpdate(
          guildId: 'guild-1',
          channelId: 'voice-1',
          selfMute: true,
          selfDeaf: false,
        ),
        {
          'op': 4,
          'd': {
            'guild_id': 'guild-1',
            'channel_id': 'voice-1',
            'self_mute': true,
            'self_deaf': false,
          },
        },
      );
    });

    test('assembles credentials in either dispatch order', () {
      for (final stateFirst in [true, false]) {
        final assembler = DiscordVoiceSessionAssembler();
        final events = stateFirst
            ? [_voiceState(), _voiceServer()]
            : [_voiceServer(), _voiceState()];

        final first = assembler.accept(
          eventName: events.first.$1,
          data: events.first.$2,
          currentUserId: 'bot-1',
        );
        final credentials = assembler.accept(
          eventName: events.last.$1,
          data: events.last.$2,
          currentUserId: 'bot-1',
        );

        expect(first, isNull);
        expect(credentials?.guildId, 'guild-1');
        expect(credentials?.channelId, 'voice-1');
        expect(credentials?.sessionId, 'session-1');
        expect(credentials?.endpoint, 'voice.example.test');
      }
    });

    test('ignores voice state updates for other users', () {
      final assembler = DiscordVoiceSessionAssembler();
      assembler.accept(
        eventName: 'VOICE_SERVER_UPDATE',
        data: _voiceServer().$2,
        currentUserId: 'bot-1',
      );

      final credentials = assembler.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: {..._voiceState().$2, 'user_id': 'someone-else'},
        currentUserId: 'bot-1',
      );

      expect(credentials, isNull);
    });
  });

  group('Discord voice UDP discovery', () {
    test('writes the exact 74-byte big-endian request', () {
      final packet = DiscordVoiceDiscoveryPacket.request(0x01020304);

      expect(packet, hasLength(74));
      expect(packet.sublist(0, 8), [0, 1, 0, 70, 1, 2, 3, 4]);
      expect(packet.sublist(8), everyElement(0));
    });

    test('parses the external address and port response', () {
      final packet = Uint8List(74);
      ByteData.sublistView(packet)
        ..setUint16(0, 2, Endian.big)
        ..setUint16(2, 70, Endian.big)
        ..setUint32(4, 42, Endian.big)
        ..setUint16(72, 50000, Endian.big);
      final address = ascii.encode('203.0.113.7');
      packet.setRange(8, 8 + address.length, address);

      final result = DiscordVoiceDiscoveryPacket.parse(packet);

      expect(result?.address, '203.0.113.7');
      expect(result?.port, 50000);
    });
  });

  group('Discord Voice Gateway v8', () {
    test('builds identify, resume, heartbeat, and protocol payloads', () {
      final protocol = DiscordVoiceGatewayProtocol(
        credentials: _credentials,
        maxDaveProtocolVersion: 1,
      )..acceptSequence(19);

      expect(protocol.identify(), {
        'op': 0,
        'd': {
          'server_id': 'guild-1',
          'user_id': 'bot-1',
          'session_id': 'session-1',
          'token': 'voice-token',
          'max_dave_protocol_version': 1,
        },
      });
      expect(protocol.resume()['d'], {
        'server_id': 'guild-1',
        'session_id': 'session-1',
        'token': 'voice-token',
        'seq_ack': 19,
      });
      expect(protocol.heartbeat(123)['d'], {'t': 123, 'seq_ack': 19});
      expect(
        protocol.selectProtocol(
          address: '203.0.113.7',
          port: 50000,
          mode: 'aead_aes256_gcm_rtpsize',
        ),
        {
          'op': 1,
          'd': {
            'protocol': 'udp',
            'data': {
              'address': '203.0.113.7',
              'port': 50000,
              'mode': 'aead_aes256_gcm_rtpsize',
            },
          },
        },
      );
    });

    test('reaches transport ready and routes DAVE binary frames', () async {
      final socket = _FakeVoiceWebSocket();
      final connector = _FakeVoiceSocketConnector(socket);
      final udp = _FakeVoiceUdpTransport();
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 1,
        socketConnector: connector,
        udpTransport: udp,
      );
      final events = <VoiceSignalingEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(client.close);

      await client.connect();
      expect(connector.connectCount, 1);
      expect(connector.lastUri.toString(), 'wss://voice.example.test?v=8');
      expect(_jsonAt(socket.sent, 0)['op'], 0);

      socket.addJson({
        'op': 2,
        'seq': 10,
        'd': {
          'ssrc': 42,
          'ip': '198.51.100.4',
          'port': 50001,
          'modes': ['aead_aes256_gcm_rtpsize'],
        },
      });
      await _flushEvents();

      expect(udp.discoveredHost, '198.51.100.4');
      expect(udp.discoveredPort, 50001);
      expect(_jsonAt(socket.sent, 1)['op'], 1);

      socket.addJson({
        'op': 4,
        'seq': 11,
        'd': {
          'mode': 'aead_aes256_gcm_rtpsize',
          'secret_key': List<int>.generate(32, (index) => index),
          'dave_protocol_version': 1,
        },
      });
      socket.addBinary([0, 12, 25, 7, 8, 9]);
      await _flushEvents();

      final ready = events.whereType<VoiceTransportReadyEvent>().single;
      expect(ready.session.address, '203.0.113.7');
      expect(ready.session.port, 50000);
      expect(ready.session.ssrc, 42);
      final dave = events.whereType<VoiceDaveBinaryEvent>().single;
      expect(dave.sequence, 12);
      expect(dave.opcode, 25);
      expect(dave.payload, [7, 8, 9]);

      socket.addJson({
        'op': 5,
        'seq': 13,
        'd': {'user_id': 'remote-1', 'ssrc': 77, 'speaking': 1},
      });
      await _flushEvents();

      final speaking = events.whereType<VoiceSpeakingEvent>().single;
      expect(speaking.userId, 'remote-1');
      expect(speaking.isSpeaking, isTrue);
      expect(client.userIdForSsrc(77), 'remote-1');

      socket.addJson({
        'op': 12,
        'seq': 14,
        'd': {'user_id': 'remote-1'},
      });
      await _flushEvents();

      expect(client.userIdForSsrc(77), isNull);
      expect(events.whereType<VoiceUserDisconnectedEvent>(), hasLength(1));

      client.sendDaveMessage(opcode: 26, payload: [3, 2, 1]);
      expect(socket.sent.last, isA<Uint8List>());
      expect(socket.sent.last, [26, 3, 2, 1]);
    });

    test('treats close code 4017 as terminal', () async {
      final socket = _FakeVoiceWebSocket();
      final connector = _FakeVoiceSocketConnector(socket);
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: connector,
        udpTransport: _FakeVoiceUdpTransport(),
      );
      final statuses = <VoiceSignalingStatusEvent>[];
      final subscription = client.events.listen((event) {
        if (event is VoiceSignalingStatusEvent) statuses.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(client.close);

      await client.connect();
      await socket.closeFromServer(4017);
      await _flushEvents();

      expect(connector.connectCount, 1);
      expect(statuses.last.status, VoiceConnectionStatus.failure);
      expect(statuses.last.error.toString(), contains('4017'));
    });

    test('routes DAVE gateway frames through the native boundary', () async {
      final socket = _FakeVoiceWebSocket();
      final daveService = _GatewayFakeDaveService();
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 1,
        daveService: daveService,
        socketConnector: _FakeVoiceSocketConnector(socket),
        udpTransport: _FakeVoiceUdpTransport(),
      );
      addTearDown(client.close);

      await client.connect();
      socket.addBinary([0, 1, 25, 4, 5, 6]);
      await _flushEvents();

      expect(daveService.session?.externalSender, [4, 5, 6]);
      expect(socket.sent.last, [26, 9, 8]);

      socket.addBinary([0, 2, 29, 0, 7, 3, 2, 1]);
      await _flushEvents();

      expect(daveService.session?.commit, [3, 2, 1]);
      expect(_jsonAt(socket.sent, socket.sent.length - 1), {
        'op': 23,
        'd': {'transition_id': 7},
      });
    });
  });
}

(String, Map<String, Object?>) _voiceState() => (
  'VOICE_STATE_UPDATE',
  {
    'guild_id': 'guild-1',
    'channel_id': 'voice-1',
    'user_id': 'bot-1',
    'session_id': 'session-1',
  },
);

(String, Map<String, Object?>) _voiceServer() => (
  'VOICE_SERVER_UPDATE',
  {
    'guild_id': 'guild-1',
    'token': 'voice-token',
    'endpoint': 'voice.example.test',
  },
);

const _credentials = VoiceServerCredentials(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'bot-1',
  sessionId: 'session-1',
  token: 'voice-token',
  endpoint: 'voice.example.test',
);

Map<String, Object?> _jsonAt(List<Object> values, int index) =>
    (jsonDecode(values[index] as String) as Map).cast<String, Object?>();

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _FakeVoiceSocketConnector implements DiscordVoiceSocketConnector {
  _FakeVoiceSocketConnector(this.socket);

  final _FakeVoiceWebSocket socket;
  int connectCount = 0;
  Uri? lastUri;

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async {
    connectCount++;
    lastUri = uri;
    return socket;
  }
}

final class _FakeVoiceWebSocket implements DiscordVoiceWebSocket {
  final StreamController<Object?> _messages = StreamController.broadcast();
  final List<Object> sent = [];
  bool _closed = false;

  @override
  int? closeCode;

  @override
  Stream<Object?> get messages => _messages.stream;

  void addJson(Map<String, Object?> payload) =>
      _messages.add(jsonEncode(payload));

  void addBinary(List<int> payload) =>
      _messages.add(Uint8List.fromList(payload));

  Future<void> closeFromServer(int code) async {
    closeCode = code;
    await _closeMessages();
  }

  @override
  void send(Object data) => sent.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCode ??= code;
    await _closeMessages();
  }

  Future<void> _closeMessages() async {
    if (_closed) return;
    _closed = true;
    await _messages.close();
  }
}

final class _FakeVoiceUdpTransport implements DiscordVoiceUdpTransport {
  final StreamController<Uint8List> _packets = StreamController.broadcast();
  String? discoveredHost;
  int? discoveredPort;
  bool _closed = false;

  @override
  Stream<Uint8List> get packets => _packets.stream;

  @override
  Future<DiscordVoiceIpDiscovery> discover({
    required String host,
    required int port,
    required int ssrc,
  }) async {
    discoveredHost = host;
    discoveredPort = port;
    return const DiscordVoiceIpDiscovery(address: '203.0.113.7', port: 50000);
  }

  @override
  int send(Uint8List packet) => packet.length;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _packets.close();
  }
}

final class _GatewayFakeDaveService implements VoiceDaveService {
  _GatewayFakeDaveSession? session;

  @override
  int get maxProtocolVersion => 1;

  @override
  VoiceDaveEncryptor createEncryptor() =>
      throw UnsupportedError('Media encryption is outside this test');

  @override
  VoiceDaveDecryptor createDecryptor() =>
      throw UnsupportedError('Media decryption is outside this test');

  @override
  VoiceDaveSession createSession({
    required int protocolVersion,
    required String channelId,
    required String selfUserId,
  }) => session = _GatewayFakeDaveSession(protocolVersion);
}

final class _GatewayFakeDaveSession implements VoiceDaveSession {
  _GatewayFakeDaveSession(this._version);

  int _version;
  List<int>? externalSender;
  List<int>? commit;

  @override
  int get protocolVersion => _version;

  @override
  VoiceDaveKeyRatchet getKeyRatchet(String userId) =>
      throw UnsupportedError('Key ratchets are outside this test');

  @override
  void setProtocolVersion(int version) => _version = version;

  @override
  void setExternalSender(List<int> package) =>
      externalSender = List.of(package);

  @override
  List<int> createKeyPackage() => [9, 8];

  @override
  List<int> processProposals({
    required List<int> proposals,
    required List<String> recognizedUserIds,
  }) => [6];

  @override
  DaveCommitResult processCommit(List<int> commit) {
    this.commit = List.of(commit);
    return const DaveCommitResult(
      status: DaveCommitStatus.ignored,
      rosterUserIds: [],
    );
  }

  @override
  DaveCommitResult processWelcome({
    required List<int> welcome,
    required List<String> recognizedUserIds,
  }) => const DaveCommitResult(
    status: DaveCommitStatus.applied,
    rosterUserIds: ['bot-1'],
  );

  @override
  void reset() => _version = 0;

  @override
  void dispose() {}
}
