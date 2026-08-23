import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/data/discord/discord_voice_websocket.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_dave.dart';

const _credentials = VoiceServerCredentials(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
  sessionId: 'session-1',
  token: 'voice-token',
  endpoint: 'voice.example.test',
);

const _streamKey = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

void main() {
  group('DiscordVoiceGatewaySocketFactory', () {
    test('a call socket offers the room DAVE version and carries the group',
        () async {
      final socket = _FakeVoiceWebSocket();
      final dave = _CountingDaveService();
      final factory = _factory(socket, dave);
      final client = factory.callSocket(_credentials);
      addTearDown(client.close);

      await client.connect();

      final identify = _identifyOn(socket);
      expect(identify['max_dave_protocol_version'], 1);
      expect(identify['channel_id'], 'voice-1');
      expect(identify['video'], isFalse);
      expect(identify.containsKey('streams'), isFalse);

      // The service rides the socket: a DAVE binary frame reaches the group
      // machinery instead of being dropped.
      socket.addBinary([0, 1, 25, 4, 5, 6]);
      await _flushEvents();
      expect(dave.sessions, 1);
    });

    test('a stream socket says it carries a screen and matches the call', () async {
      final socket = _FakeVoiceWebSocket();
      final dave = _CountingDaveService();
      final factory = _factory(socket, dave);
      final client = factory.streamSocket(
        credentials: _credentials,
        streamKey: _streamKey,
      );
      addTearDown(client.close);

      await client.connect();

      // The version is the call's even though the socket joins no group:
      // offering 0 against a v1 call is refused.
      final identify = _identifyOn(socket);
      expect(identify['max_dave_protocol_version'], 1);
      expect(identify.containsKey('channel_id'), isFalse);
      expect(identify['video'], isTrue);
      expect(identify['streams'], [
        {'type': 'screen', 'rid': '100', 'quality': 100},
      ]);

      // A group of its own: a stream is a separate media session with a
      // separate MLS group, so the same frame the call's socket would hand
      // to the service reaches it here too.
      socket.addBinary([0, 1, 25, 4, 5, 6]);
      await _flushEvents();
      expect(dave.sessions, 1);
      // The call's group is its voice channel.
      expect(dave.groupIds.single, 'voice-1');
    });

    test('a stream keys its DAVE group one below the RTC server id', () async {
      final socket = _FakeVoiceWebSocket();
      final dave = _CountingDaveService();
      final factory = _factory(socket, dave);
      // The stream credentials an endpoint hands over: the RTC server id as
      // the server, its channel as the channel.
      const credentials = VoiceServerCredentials(
        guildId: '1541148819067248681',
        channelId: '1541148819067248682',
        userId: 'me',
        sessionId: 'session-1',
        token: 'stream-token',
        endpoint: 'stream.discord.gg',
      );
      final client = factory.streamSocket(
        credentials: credentials,
        streamKey: _streamKey,
      );
      addTearDown(client.close);

      await client.connect();
      socket.addBinary([0, 1, 25, 4, 5, 6]);
      await _flushEvents();

      // A session keyed by the RTC channel signs its key packages against a
      // group the server does not recognise, and the roster never names the
      // account. Discord's media stack keys a stream's group one below the
      // RTC server id.
      expect(dave.groupIds.single, '1541148819067248680');
    });

    test('a session without DAVE offers version 0 on both kinds', () async {
      final callSocket = _FakeVoiceWebSocket();
      final call = _factory(callSocket).callSocket(_credentials);
      addTearDown(call.close);
      await call.connect();

      final streamSocket = _FakeVoiceWebSocket();
      final stream = _factory(streamSocket).streamSocket(
        credentials: _credentials,
        streamKey: _streamKey,
      );
      addTearDown(stream.close);
      await stream.connect();

      // Zero is what tells Discord to stay on the transport cipher rather
      // than negotiating a group this session could not join.
      expect(_identifyOn(callSocket)['max_dave_protocol_version'], 0);
      expect(_identifyOn(streamSocket)['max_dave_protocol_version'], 0);
    });
  });
}

DiscordVoiceGatewaySocketFactory _factory(
  _FakeVoiceWebSocket socket, [
  _CountingDaveService? dave,
]) => DiscordVoiceGatewaySocketFactory(
  daveService: dave,
  socketConnector: _FakeVoiceSocketConnector(socket),
);

Map<String, Object?> _identifyOn(_FakeVoiceWebSocket socket) {
  final identify = jsonDecode(socket.sent.single as String) as Map;
  expect(identify['op'], 0);
  return identify['d'] as Map<String, Object?>;
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _FakeVoiceSocketConnector implements DiscordVoiceSocketConnector {
  _FakeVoiceSocketConnector(this.socket);

  final _FakeVoiceWebSocket socket;

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async => socket;
}

final class _FakeVoiceWebSocket implements DiscordVoiceWebSocket {
  final StreamController<Object?> _messages = StreamController.broadcast();
  final List<Object> sent = [];

  @override
  int? closeCode;

  @override
  Stream<Object?> get messages => _messages.stream;

  void addJson(Map<String, Object?> payload) =>
      _messages.add(jsonEncode(payload));

  void addBinary(List<int> payload) =>
      _messages.add(Uint8List.fromList(payload));

  @override
  void send(Object data) => sent.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCode = code;
    await _messages.close();
  }
}

/// Records group activity without doing any of it.
final class _CountingDaveService implements VoiceDaveService {
  int sessions = 0;
  final List<String> groupIds = [];

  @override
  int get maxProtocolVersion => 1;

  @override
  VoiceDaveEncryptor createEncryptor() =>
      throw UnsupportedError('Encryption is outside this test');

  @override
  VoiceDaveDecryptor createDecryptor() =>
      throw UnsupportedError('Decryption is outside this test');

  @override
  VoiceDaveSession createSession({
    required int protocolVersion,
    required String channelId,
    required String selfUserId,
  }) {
    sessions++;
    groupIds.add(channelId);
    return _InertDaveSession();
  }
}

final class _InertDaveSession implements VoiceDaveSession {
  @override
  int get protocolVersion => 0;

  @override
  VoiceDaveKeyRatchet getKeyRatchet(String userId) =>
      throw UnsupportedError('Key ratchets are outside this test');

  @override
  void setProtocolVersion(int version) {}

  @override
  void setExternalSender(List<int> package) {}

  @override
  List<int> createKeyPackage() => const [9, 8];

  @override
  List<int> processProposals({
    required List<int> proposals,
    required List<String> recognizedUserIds,
  }) => throw UnsupportedError('Proposals are outside this test');

  @override
  DaveCommitResult processCommit(List<int> commit) =>
      throw UnsupportedError('Commits are outside this test');

  @override
  DaveCommitResult processWelcome({
    required List<int> welcome,
    required List<String> recognizedUserIds,
  }) => throw UnsupportedError('Welcomes are outside this test');

  @override
  void reset() {}

  @override
  void dispose() {}
}
