import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_etf_codec.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _currentUserId = '333333333333333333';
const _guildId = '111111111111111111';
const _goneGuildId = '444444444444444444';
const _keptChannelId = '222222222222222222';
const _deletedChannelId = '555555555555555555';
const _newChannelId = '888888888888888888';
const _dmChannelId = '666666666666666666';
const _recipientId = '777777777777777777';
const _ackedMessage = '123456789012345678';
const _newestMessage = '987654321098765432';
const _heldMessage = '999999999999999999';

void main() {
  setUpAll(sqfliteFfiInit);

  int identifies(_MemoryDesktopWebSocket socket) =>
      socket.terms.where((frame) => frame['op'] == 2).length;

  Future<
    (
      DiscordDesktopChatRepository,
      _MemoryDesktopWebSocket,
      List<ChatRepositoryEvent>,
    )
  >
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
        transport: _FakeTransport(),
      ),
      gateway,
      cache,
    );
    final events = <ChatRepositoryEvent>[];
    addTearDown(repository.close);
    final loading = repository.loadWorkspace();
    await _waitFor(() => socket.isOpen);
    socket.receiveTerm(const {
      'op': 10,
      'd': {'heartbeat_interval': 60000},
    });
    await _waitFor(() => identifies(socket) == 1);
    socket.receiveTerm(_firstReady);
    await loading;
    events.clear();
    repository.events.listen(events.add);
    return (repository, socket, events);
  }

  Future<void> reconnect(_MemoryDesktopWebSocket socket) async {
    // An invalid session is the reconnect that cannot resume: the client
    // identifies again, and Discord answers with a fresh READY.
    socket.receiveTerm(const {'op': 9, 'd': false});
    await _waitFor(() => identifies(socket) == 2);
  }

  Map<String, Object?> identifyClientState(_MemoryDesktopWebSocket socket) {
    final identify = socket.terms.lastWhere((frame) => frame['op'] == 2);
    return (identify['d']! as Map)['client_state']! as Map<String, Object?>;
  }

  test(
    'a reconnect identify echoes the versions the last READY committed',
    () async {
      final (repository, socket, _) = await connect();

      await reconnect(socket);

      expect(identifyClientState(socket), {
        'guild_versions': <String, Object?>{},
        'read_state_version': 21,
        'user_guild_settings_version': 4,
        'highest_last_message_id': _newestMessage,
        'private_channels_version': _newestMessage,
      });
      expect(repository.readState!.current.readStateVersion, 21);
    },
  );

  test('a reconnect READY updates guilds and channels in place', () async {
    final (repository, socket, events) = await connect();

    await reconnect(socket);
    socket.receiveTerm(_secondReady);
    await _waitFor(
      () =>
          events.whereType<ChannelUpsertedEvent>().length == 2 &&
          events.whereType<ChannelDeletedEvent>().isNotEmpty,
    );
    await _drain();

    // The server the READY stopped naming is gone from the rail, and so is
    // its channel; the kept channel arrives renamed next to a new one.
    expect(
      events.whereType<SpaceRemovedEvent>().map((event) => event.spaceId),
      [_goneGuildId],
    );
    expect(
      events.whereType<ChannelDeletedEvent>().map((event) => event.channelId),
      [_deletedChannelId],
    );
    final upserts = events.whereType<ChannelUpsertedEvent>().toList();
    expect(
      upserts.map((event) => event.channel.id),
      containsAll([_keptChannelId, _newChannelId]),
    );
    expect(
      upserts
          .firstWhere((event) => event.channel.id == _keptChannelId)
          .channel
          .name,
      'renamed',
    );
    // The kept server itself is unchanged, so it announces nothing, and the
    // unchanged direct message neither.
    expect(events.whereType<SpaceUpsertedEvent>(), isEmpty);

    // Read state keeps folding on the reconnect: the fresh READY replaced the
    // baseline with the one it carried.
    expect(repository.readState!.current.readStateVersion, 22);
  });

  test('a reconnect keeps the history the workspace already held', () async {
    final (repository, socket, events) = await connect();
    final page = await repository.loadChannelHistory(_keptChannelId);
    final held = page.history.messages.length;
    expect(held, 1);

    await reconnect(socket);
    socket.receiveTerm(_secondReady);
    await _waitFor(() => events.whereType<ChannelUpsertedEvent>().isNotEmpty);
    await _drain();

    // The renamed channel is still the account's channel, and the history
    // held for it survives the in-place hydration instead of being dropped
    // with a wholesale rebuild.
    final next = await repository.loadChannelHistory(_keptChannelId);
    expect(next.history.messages.map((message) => message.id), [_heldMessage]);
  });
}

Map<String, Object?> _channel(String id, String name, String lastMessageId) => {
  'id': id,
  'type': 0,
  'name': name,
  'last_message_id': lastMessageId,
  'permission_overwrites': <Object?>[],
};

Map<String, Object?> _guild(String id, String name, List<Object?> channels) => {
  'id': id,
  'name': name,
  'roles': [
    {'id': id, 'name': '@everyone', 'permissions': '1024'},
  ],
  'channels': channels,
};

final Map<String, Object?> _firstReady = _readyDispatch(
  1,
  _readyPayload(
    guilds: [
      _guild(_guildId, 'Kept', [
        _channel(_keptChannelId, 'general', _ackedMessage),
      ]),
      _guild(_goneGuildId, 'Gone', [
        _channel(_deletedChannelId, 'doomed', _ackedMessage),
      ]),
    ],
  ),
);

final Map<String, Object?> _secondReady = _readyDispatch(
  2,
  _readyPayload(
    readStateVersion: 22,
    guilds: [
      _guild(_guildId, 'Kept', [
        _channel(_keptChannelId, 'renamed', _newestMessage),
        _channel(_newChannelId, 'fresh', _ackedMessage),
      ]),
    ],
  ),
);

Map<String, Object?> _readyDispatch(int sequence, Map<String, Object?> data) =>
    {'op': 0, 's': sequence, 't': 'READY', 'd': data};

Map<String, Object?> _readyPayload({
  required List<Map<String, Object?>> guilds,
  int readStateVersion = 21,
}) => {
  'session_id': 'session',
  'user': {'id': _currentUserId, 'username': 'member'},
  'users': [
    {
      'id': _recipientId,
      'username': 'jack',
      'global_name': 'Jack',
      'avatar': null,
    },
  ],
  'guilds': guilds,
  'private_channels': [
    {
      'id': _dmChannelId,
      'type': 1,
      'recipient_ids': [_recipientId],
      'last_message_id': _newestMessage,
    },
  ],
  'read_state': {
    'version': readStateVersion,
    'partial': false,
    'entries': [
      {
        'id': _keptChannelId,
        'last_message_id': _ackedMessage,
        'mention_count': 1,
      },
      {'id': _dmChannelId, 'last_message_id': _newestMessage},
    ],
  },
  'user_guild_settings': {
    'version': 4,
    'partial': false,
    'entries': [
      {'guild_id': _guildId, 'muted': true},
    ],
  },
};

/// Drives the socket with ETF terms, so it selects that encoding explicitly.
/// The shipped default is JSON until ETF has decoded a real authenticated
/// READY rather than only a HELLO.
const _uncompressed = DiscordDesktopProtocolProfile(
  clientBuildNumber: 582977,
  gatewayEncoding: 'etf',
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

Future<void> _drain() => Future<void>.delayed(const Duration(milliseconds: 30));

final class _FakeTransport implements DiscordHttpTransport {
  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    if (uri.path == '/api/v9/gateway') {
      return _json({'url': 'wss://gateway.discord.gg'});
    }
    if (uri.path == '/api/v9/channels/$_keptChannelId/messages') {
      return _json([
        {
          'id': _heldMessage,
          'channel_id': _keptChannelId,
          'author': {
            'id': _recipientId,
            'username': 'jack',
            'global_name': 'Jack',
          },
          'content': 'hello',
          'timestamp': '2026-07-25T10:00:00+00:00',
        },
      ]);
    }
    throw StateError('Unexpected REST call: ${uri.path}');
  }

  static DiscordHttpResponse _json(Object payload) => DiscordHttpResponse(
    statusCode: 200,
    headers: const {},
    body: jsonEncode(payload),
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
