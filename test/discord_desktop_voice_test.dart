import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/disconnected_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_etf_codec.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_dave.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('joins and leaves a voice channel on the desktop-user session', () async {
    final socket = _MemoryDesktopWebSocket();
    final repository = await _openRepository(socket);
    addTearDown(repository.close);

    final workspace = await _bootstrap(repository, socket);
    expect(workspace.currentMemberId, 'me');

    final voice = repository.voiceSignaling;
    expect(voice, isNotNull, reason: 'the desktop session carries voice');

    await voice!.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');

    // R08: the desktop renderer always sends all six fields, so a body missing
    // self_video or flags is a tell that the session is not the client it says.
    expect(_lastVoiceState(socket), {
      'guild_id': 'guild-1',
      'channel_id': 'voice-1',
      'self_mute': false,
      'self_deaf': false,
      'self_video': false,
      'flags': 0,
    });

    await voice.joinVoiceChannel(
      guildId: 'guild-1',
      channelId: 'voice-1',
      selfMute: true,
    );
    expect(_lastVoiceState(socket)['self_mute'], isTrue);

    await voice.leaveVoiceChannel('guild-1');
    expect(_lastVoiceState(socket)['channel_id'], isNull);
  });

  test('seats the members already in the room when joining', () async {
    final socket = _MemoryDesktopWebSocket();
    final repository = await _openRepository(socket);
    addTearDown(repository.close);

    // The occupants ride in on the bootstrap GUILD_CREATE burst — before the
    // workspace resolves, and long before the user picks a channel.
    await _bootstrap(
      repository,
      socket,
      guildCreate: const {
        'id': 'guild-1',
        'voice_states': [
          {'user_id': 'member-1', 'channel_id': 'voice-1', 'self_deaf': true},
          {'user_id': 'member-2', 'channel_id': 'voice-2'},
        ],
      },
    );

    final voice = repository.voiceSignaling!;
    final states = <VoiceParticipantStateEvent>[];
    final subscription = voice.voiceEvents.listen((event) {
      if (event is VoiceParticipantStateEvent) states.add(event);
    });
    addTearDown(subscription.cancel);

    await voice.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
    await _settle();

    expect(states.map((state) => state.userId), ['member-1']);
    expect(states.single.selfDeafened, isTrue);
  });

  test('asks the repository for voice instead of testing its type', () async {
    final offline = ChatController(const DisconnectedChatRepository());
    addTearDown(offline.dispose);
    expect(offline.voiceSignalingService, isNull);

    final repository = await _openRepository(_MemoryDesktopWebSocket());
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    expect(
      controller.voiceSignalingService,
      same(repository.voiceSignaling),
      reason: 'the contract is the only channel the controller reads',
    );
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
) async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  return DiscordDesktopChatRepository(
    DiscordDesktopApiClient(
      authorization: 'account-session',
      headers: const {},
      transport: _GatewayUrlTransport(),
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

/// Drives READY plus READY_SUPPLEMENTAL, which is what shortens the bootstrap
/// settle timer from two seconds to the supplemental's 350 ms.
Future<ChatWorkspace> _bootstrap(
  DiscordDesktopChatRepository repository,
  _MemoryDesktopWebSocket socket, {
  Map<String, Object?>? guildCreate,
}) async {
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
            {'id': 'voice-1', 'type': 2, 'name': 'General Voice'},
          ],
        },
      ],
      'private_channels': <Object?>[],
    },
  });
  if (guildCreate != null) {
    socket.receiveTerm({
      'op': 0,
      's': 2,
      't': 'GUILD_CREATE',
      'd': guildCreate,
    });
  }
  socket.receiveTerm(const {
    'op': 0,
    's': 3,
    't': 'READY_SUPPLEMENTAL',
    'd': {'lazy_private_channels': <Object?>[]},
  });
  return workspaceFuture;
}

Map<String, Object?> _lastVoiceState(_MemoryDesktopWebSocket socket) {
  final frame = socket.terms.lastWhere((term) => term['op'] == 4);
  return (frame['d']! as Map).cast<String, Object?>();
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _GatewayUrlTransport implements DiscordHttpTransport {
  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async => const DiscordHttpResponse(
    statusCode: 200,
    headers: {},
    body: '{"url":"wss://gateway.discord.gg"}',
  );

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
