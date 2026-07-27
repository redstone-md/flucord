import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_etf_codec.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_dave.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'subscribes, joins and leaves a DM call on the desktop session',
    () async {
      final socket = _MemoryDesktopWebSocket();
      final transport = _CallTransport();
      final repository = await _openRepository(socket, transport);
      addTearDown(repository.close);
      await _bootstrap(repository, socket);

      final calls = repository.directCalls;
      expect(calls, isNotNull, reason: 'the desktop session can place calls');

      calls!.watchChannel('dm-1');
      // R08: opcode 13 CALL_CONNECT carries only the channel id, and nothing
      // about a call is pushed to a session that has not sent it.
      expect(_frames(socket, 13).last, {'channel_id': 'dm-1'});

      await calls.joinCall(channelId: 'dm-1');
      // R08: the DM form of opcode 4 is the same six fields with a null guild.
      expect(_frames(socket, 4).last, {
        'guild_id': null,
        'channel_id': 'dm-1',
        'self_mute': false,
        'self_deaf': false,
        'self_video': false,
        'flags': 0,
      });

      await calls.joinCall(channelId: 'dm-1', selfMute: true);
      expect(_frames(socket, 4).last['self_mute'], isTrue);

      await calls.leaveCall('dm-1');
      expect(_frames(socket, 4).last['channel_id'], isNull);
    },
  );

  test('assembles DM call credentials from the guildless pair', () async {
    final socket = _MemoryDesktopWebSocket();
    final repository = await _openRepository(socket, _CallTransport());
    addTearDown(repository.close);
    await _bootstrap(repository, socket);

    final credentials = <VoiceServerCredentials>[];
    final subscription = repository.voiceSignaling!.voiceEvents.listen((event) {
      if (event is VoiceCredentialsReadyEvent) {
        credentials.add(event.credentials);
      }
    });
    addTearDown(subscription.cancel);

    await repository.directCalls!.joinCall(channelId: 'dm-1');
    // R08: a DM's self voice state omits guild_id and its VOICE_SERVER_UPDATE
    // names the channel instead, so the pair keys on the channel.
    socket.receiveTerm(const {
      'op': 0,
      's': 10,
      't': 'VOICE_STATE_UPDATE',
      'd': {
        'user_id': 'me',
        'channel_id': 'dm-1',
        'session_id': 'voice-session',
      },
    });
    socket.receiveTerm(const {
      'op': 0,
      's': 11,
      't': 'VOICE_SERVER_UPDATE',
      'd': {
        'guild_id': null,
        'channel_id': 'dm-1',
        'token': 'voice-token',
        'endpoint': 'voice.example.test',
      },
    });
    await _settle();

    expect(credentials, hasLength(1));
    expect(credentials.single.guildId, isNull);
    expect(credentials.single.channelId, 'dm-1');
    // The voice gateway wants the channel as server_id when there is no guild.
    expect(credentials.single.serverId, 'dm-1');
    expect(credentials.single.sessionId, 'voice-session');
  });

  test('seats the people already in the call and reports departures', () async {
    final socket = _MemoryDesktopWebSocket();
    final repository = await _openRepository(socket, _CallTransport());
    addTearDown(repository.close);
    await _bootstrap(repository, socket);

    // CALL_CREATE lands as soon as the channel is subscribed, before the user
    // decides to answer.
    repository.directCalls!.watchChannel('dm-1');
    socket.receiveTerm(const {
      'op': 0,
      's': 10,
      't': 'CALL_CREATE',
      'd': {
        'channel_id': 'dm-1',
        'message_id': 'call-message',
        'voice_states': [
          {'user_id': 'friend-1', 'self_mute': true},
        ],
      },
    });
    await _settle();

    final states = <VoiceParticipantStateEvent>[];
    final subscription = repository.voiceSignaling!.voiceEvents.listen((event) {
      if (event is VoiceParticipantStateEvent) states.add(event);
    });
    addTearDown(subscription.cancel);

    await repository.directCalls!.joinCall(channelId: 'dm-1');
    await _settle();

    expect(states.map((state) => state.userId), ['friend-1']);
    expect(states.single.guildId, isNull);
    expect(states.single.selfMuted, isTrue);

    socket.receiveTerm(const {
      'op': 0,
      's': 11,
      't': 'VOICE_STATE_UPDATE',
      'd': {'user_id': 'friend-1', 'channel_id': null},
    });
    await _settle();

    expect(states.last.userId, 'friend-1');
    expect(states.last.channelId, isNull);
  });

  test('rings and stops ringing over the documented routes', () async {
    final socket = _MemoryDesktopWebSocket();
    final transport = _CallTransport()..ringable = true;
    final repository = await _openRepository(socket, transport);
    addTearDown(repository.close);
    await _bootstrap(repository, socket);
    final calls = repository.directCalls!;

    expect(await calls.isRingable('dm-1'), isTrue);
    expect(transport.requests.last.$1, 'GET');
    expect(transport.requests.last.$2, endsWith('/channels/dm-1/call'));

    socket.receiveTerm(const {
      'op': 0,
      's': 10,
      't': 'CALL_CREATE',
      'd': {'channel_id': 'dm-1', 'message_id': 'call-message'},
    });
    await _settle();

    await calls.ring('dm-1');
    expect(transport.requests.last.$2, endsWith('/channels/dm-1/call/ring'));
    expect(transport.requests.last.$3, {
      'recipients': null,
      'analytics_location': 'dm_invite',
    });

    await calls.stopRinging('dm-1');
    expect(
      transport.requests.last.$2,
      endsWith('/channels/dm-1/call/stop-ringing'),
    );
    // R08 drops the key entirely on a self decline rather than sending null.
    expect(transport.requests.last.$3, isEmpty);
  });

  test('a ring aimed at us becomes an incoming call', () async {
    final socket = _MemoryDesktopWebSocket();
    final repository = await _openRepository(socket, _CallTransport());
    addTearDown(repository.close);
    await _bootstrap(repository, socket);

    final incoming = <IncomingCall?>[];
    final subscription = repository.directCalls!.callEvents.listen((event) {
      if (event is IncomingCallChangedEvent) incoming.add(event.call);
    });
    addTearDown(subscription.cancel);

    socket.receiveTerm(const {
      'op': 0,
      's': 10,
      't': 'CALL_CREATE',
      'd': {
        'channel_id': 'dm-1',
        'message_id': 'call-message',
        'ongoing_rings': {'me': 'friend-1'},
      },
    });
    await _settle();

    expect(incoming.single?.channelId, 'dm-1');
    expect(incoming.single?.callerId, 'friend-1');

    socket.receiveTerm(const {
      'op': 0,
      's': 11,
      't': 'CALL_DELETE',
      'd': {'channel_id': 'dm-1'},
    });
    await _settle();

    expect(incoming.last, isNull);
  });

  test('re-subscribes every watched call after a replayed READY', () async {
    final socket = _MemoryDesktopWebSocket();
    final repository = await _openRepository(socket, _CallTransport());
    addTearDown(repository.close);
    await _bootstrap(repository, socket);

    repository.directCalls!.watchChannel('dm-1');
    expect(_frames(socket, 13), hasLength(1));

    // The subscription dies with the session, so a fresh READY has to replay
    // it or the client goes blind to that channel's calls.
    socket.receiveTerm(const {
      'op': 0,
      's': 20,
      't': 'READY',
      'd': {
        'session_id': 'session-2',
        'user': {'id': 'me', 'username': 'member'},
        'guilds': <Object?>[],
        'private_channels': <Object?>[],
      },
    });
    await _settle();

    expect(_frames(socket, 13), hasLength(2));
    expect(_frames(socket, 13).last, {'channel_id': 'dm-1'});
  });
}

/// The installed profile negotiates zstd-stream; these tests drive the socket
/// with plain ETF terms, so they pin the encoding without transport
/// compression.
/// Drives the socket with ETF terms, so it selects that encoding explicitly.
/// The shipped default is JSON until ETF has decoded a real authenticated
/// READY rather than only a HELLO.
const _uncompressed = DiscordDesktopProtocolProfile(
  clientBuildNumber: 582977,
  gatewayEncoding: 'etf',
);

Future<DiscordDesktopChatRepository> _openRepository(
  _MemoryDesktopWebSocket socket,
  _CallTransport transport,
) async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  return DiscordDesktopChatRepository(
    DiscordDesktopApiClient(
      authorization: 'account-session',
      headers: const {},
      transport: transport,
    ),
    DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      profile: _uncompressed,
      socketConnector: _MemoryDesktopWebSocketConnector(socket),
    ),
    cache,
    daveService: _CapabilityOnlyDaveService(),
  );
}

Future<ChatWorkspace> _bootstrap(
  DiscordDesktopChatRepository repository,
  _MemoryDesktopWebSocket socket,
) async {
  final workspaceFuture = repository.loadWorkspace();
  await _settle();
  socket.receiveTerm(const {
    'op': 0,
    's': 1,
    't': 'READY',
    'd': {
      'session_id': 'session',
      'user': {'id': 'me', 'username': 'member'},
      'guilds': [
        {
          'id': 'guild-1',
          'name': 'Guild',
          'channels': [
            {'id': 'text-1', 'type': 0, 'name': 'general'},
          ],
        },
      ],
      'private_channels': [
        {
          'id': 'dm-1',
          'type': 1,
          'recipients': [
            {'id': 'friend-1', 'username': 'friend'},
          ],
        },
      ],
    },
  });
  socket.receiveTerm(const {
    'op': 0,
    's': 2,
    't': 'READY_SUPPLEMENTAL',
    'd': {'lazy_private_channels': <Object?>[]},
  });
  return workspaceFuture;
}

List<Map<String, Object?>> _frames(
  _MemoryDesktopWebSocket socket,
  int opcode,
) => socket.terms
    .where((term) => term['op'] == opcode)
    .map((term) => (term['d'] as Map? ?? const {}).cast<String, Object?>())
    .toList(growable: false);

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _CallTransport implements DiscordHttpTransport {
  final List<(String, String, Map<String, Object?>)> requests = [];
  bool ringable = false;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final decoded = body == null || body.isEmpty
        ? const <String, Object?>{}
        : (jsonDecode(utf8.decode(body)) as Map).cast<String, Object?>();
    requests.add((method, uri.path, decoded));
    if (uri.path.endsWith('/gateway')) {
      return const DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body: '{"url":"wss://gateway.discord.gg"}',
      );
    }
    return DiscordHttpResponse(
      statusCode: 200,
      headers: const {},
      body: '{"ringable":$ringable}',
    );
  }

  @override
  void close() {}
}

final class _MemoryDesktopWebSocketConnector
    implements DiscordDesktopWebSocketConnector {
  _MemoryDesktopWebSocketConnector(this.socket);

  final DiscordDesktopWebSocket socket;

  @override
  Future<DiscordDesktopWebSocket> connect(Uri uri) async => socket;
}

final class _MemoryDesktopWebSocket implements DiscordDesktopWebSocket {
  final StreamController<Object?> _messages = StreamController();
  final List<Object> sent = [];
  bool _open = true;

  List<Map<String, Object?>> get terms => sent
      .whereType<Uint8List>()
      .map((bytes) => DiscordEtfCodec.decode(bytes)! as Map<String, Object?>)
      .toList(growable: false);

  @override
  int? get closeCode => null;

  @override
  bool get isOpen => _open;

  @override
  Stream<Object?> get messages => _messages.stream;

  void receiveTerm(Map<String, Object?> payload) =>
      _messages.add(DiscordEtfCodec.encode(payload));

  @override
  void send(String data) => sent.add(data);

  @override
  void sendBinary(List<int> data) => sent.add(Uint8List.fromList(data));

  @override
  Future<void> close() async {
    _open = false;
    if (!_messages.isClosed) await _messages.close();
  }
}

final class _CapabilityOnlyDaveService implements VoiceDaveService {
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
  }) => throw UnsupportedError('Not used by the signalling boundary');
}
