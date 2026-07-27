import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_etf_codec.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _guildId = '111111111111111111';
const _channelId = '222222222222222222';
const _currentUserId = '333333333333333333';
const _olderMessage = '123456789012345678';
const _newerMessage = '234567890123456789';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<(DiscordDesktopChatRepository, _MemoryDesktopWebSocket)>
  connect() async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final socket = _MemoryDesktopWebSocket();
    final gateway = DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      profile: _uncompressed,
      socketConnector: _MemoryDesktopWebSocketConnector(socket),
    );
    final repository = DiscordDesktopChatRepository(
      DiscordDesktopApiClient(
        authorization: 'account-session',
        headers: const {},
        transport: _UnusedTransport(),
      ),
      gateway,
      cache,
    );
    addTearDown(repository.close);
    await gateway.connect('wss://gateway.discord.gg');
    return (repository, socket);
  }

  test('the desktop session offers read state and hydrates it', () async {
    final (repository, socket) = await connect();
    final readState = repository.readState!;

    socket.receiveTerm(_ready);
    await _waitFor(() => readState.current.forChannel(_channelId) != null);

    expect(readState.current.forChannel(_channelId)!.mentionCount, 3);
    expect(
      readState.current.forChannel(_channelId)!.lastAckedId,
      _olderMessage,
    );
    expect(readState.current.settingsFor(_guildId).muted, isTrue);
    expect(readState.current.readStateVersion, 21);
  });

  test('another session moving the pointer reaches the store', () async {
    final (repository, socket) = await connect();
    final readState = repository.readState!;

    socket
      ..receiveTerm(_ready)
      ..receiveTerm(const {
        'op': 0,
        's': 2,
        't': 'MESSAGE_ACK',
        'd': {
          'channel_id': _channelId,
          'message_id': _newerMessage,
          'mention_count': 0,
          'version': 22,
        },
      });
    await _waitFor(
      () =>
          readState.current.forChannel(_channelId)?.lastAckedId ==
          _newerMessage,
    );

    expect(readState.current.forChannel(_channelId)!.mentionCount, 0);
    expect(readState.current.readStateVersion, 22);
  });

  test('PASSIVE_UPDATE_V2 republishes the last-message pointers', () async {
    final (repository, socket) = await connect();
    final events = <ChatRepositoryEvent>[];
    repository.events.listen(events.add);

    socket
      ..receiveTerm(_ready)
      ..receiveTerm(const {
        'op': 0,
        's': 2,
        't': 'PASSIVE_UPDATE_V2',
        'd': {
          'guild_id': _guildId,
          'channels': [
            {'id': _channelId, 'last_message_id': _newerMessage},
            {'id': _channelId},
            'junk',
          ],
        },
      });
    await _waitFor(
      () => events.whereType<ChannelLastMessageEvent>().isNotEmpty,
    );

    final pointer = events.whereType<ChannelLastMessageEvent>().single;
    expect(pointer.channelId, _channelId);
    expect(pointer.messageId, _newerMessage);
  });

  test('a dispatch with no channels changes nothing', () async {
    final (repository, socket) = await connect();
    final events = <ChatRepositoryEvent>[];
    repository.events.listen(events.add);

    socket
      ..receiveTerm(_ready)
      ..receiveTerm(const {
        'op': 0,
        's': 2,
        't': 'PASSIVE_UPDATE_V2',
        'd': {'guild_id': _guildId},
      });
    await _waitFor(() => events.isNotEmpty);

    expect(events.whereType<ChannelLastMessageEvent>(), isEmpty);
  });
}

const _ready = {
  'op': 0,
  's': 1,
  't': 'READY',
  'd': {
    'session_id': 'session',
    'user': {'id': _currentUserId},
    'notification_settings': {'flags': 16},
    'guilds': [
      {
        'id': _guildId,
        'roles': [
          {'id': _guildId, 'name': '@everyone', 'permissions': '1024'},
        ],
        'channels': [
          {
            'id': _channelId,
            'type': 0,
            'last_message_id': _newerMessage,
            'permission_overwrites': <Object?>[],
          },
        ],
      },
    ],
    'private_channels': <Object?>[],
    'read_state': {
      'version': 21,
      'partial': false,
      'entries': [
        {
          'id': _channelId,
          'mention_count': 3,
          'last_message_id': _olderMessage,
        },
      ],
    },
    'user_guild_settings': {
      'version': 4,
      'partial': false,
      'entries': [
        {'guild_id': _guildId, 'muted': true},
      ],
    },
  },
};

/// The installed profile negotiates zstd-stream; these tests drive the socket
/// with plain ETF terms, so they pin the encoding without compression.
const _uncompressed = DiscordDesktopProtocolProfile(clientBuildNumber: 582977);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

final class _UnusedTransport implements DiscordHttpTransport {
  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async => throw StateError('No REST call is expected');

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
