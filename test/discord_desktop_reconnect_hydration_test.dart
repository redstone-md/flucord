import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';

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

  int identifies(MemoryDesktopWebSocket socket) =>
      socket.frames.where((frame) => frame['op'] == 2).length;

  Future<
    (
      DiscordDesktopChatRepository,
      MemoryDesktopWebSocket,
      List<ChatRepositoryEvent>,
    )
  >
  connect() async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final connector = MemoryDesktopWebSocketConnector();
    final gateway = DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      profile: _uncompressed,
      socketConnector: connector,
    );
    final repository = DiscordDesktopChatRepository(
      DiscordDesktopApiClient(
        authorization: 'account-session',
        headers: const {},
        transport: _transport(),
      ),
      gateway,
      cache,
    );
    final events = <ChatRepositoryEvent>[];
    addTearDown(repository.close);
    final loading = repository.loadWorkspace();
    await _waitFor(() => connector.sockets.isNotEmpty);
    final socket = connector.sockets.single;
    socket.receive(const {
      'op': 10,
      'd': {'heartbeat_interval': 60000},
    });
    await _waitFor(() => identifies(socket) == 1);
    socket.receive(_firstReady);
    await loading;
    events.clear();
    repository.events.listen(events.add);
    return (repository, socket, events);
  }

  Future<void> reconnect(MemoryDesktopWebSocket socket) async {
    // An invalid session is the reconnect that cannot resume: the client
    // identifies again, and Discord answers with a fresh READY.
    socket.receive(const {'op': 9, 'd': false});
    await _waitFor(() => identifies(socket) == 2);
  }

  Map<String, Object?> identifyClientState(MemoryDesktopWebSocket socket) {
    final identify = socket.frames.lastWhere((frame) => frame['op'] == 2);
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
    socket.receive(_secondReady);
    await _waitFor(() => events.whereType<WorkspaceDiffEvent>().isNotEmpty);
    await _drain();

    // The server the READY stopped naming is gone from the rail, and so is
    // its channel; the kept channel arrives renamed next to a new one.
    final diff = events.whereType<WorkspaceDiffEvent>().single.diff;
    expect(diff.removedSpaceIds, {_goneGuildId});
    expect(diff.removedChannelIds, {_deletedChannelId});
    expect(
      {for (final channel in diff.channels) channel.id: channel.name},
      {_keptChannelId: 'renamed', _newChannelId: 'fresh'},
    );
    // The kept server itself is unchanged, so it announces nothing, and the
    // unchanged direct message neither.
    expect(diff.spaces, isEmpty);

    // Read state keeps folding on the reconnect: the fresh READY replaced the
    // baseline with the one it carried.
    expect(repository.readState!.current.readStateVersion, 22);
  });

  test('a READY that changes 5000 channels emits one event for them', () async {
    final (_, socket, events) = await connect();

    await reconnect(socket);
    socket.receive(
      _readyDispatch(
        2,
        _readyPayload(
          guilds: [
            rawGuild(
              id: _guildId,
              name: 'Kept',
              channels: [
                for (var index = 0; index < 5000; index++)
                  rawChannel(id: '${6100000000000 + index}', name: 'c$index'),
              ],
            ),
          ],
        ),
      ),
    );
    await _waitFor(() => events.whereType<WorkspaceDiffEvent>().isNotEmpty);
    await _drain();

    final diff = events.whereType<WorkspaceDiffEvent>().single.diff;
    expect(diff.channels, hasLength(5000));
    expect(events.whereType<ChannelUpsertedEvent>(), isEmpty);
    expect(events.whereType<ChannelDeletedEvent>(), isEmpty);
  });

  group('a guild deleted between READY and READY_SUPPLEMENTAL', () {
    Future<List<ChatRepositoryEvent>> deleteThenSupplement(
      Map<String, Object?> deletion,
    ) async {
      final (_, socket, events) = await connect();
      await reconnect(socket);
      socket.receive(_readyDispatch(2, _firstReadyPayload));
      await _waitFor(() => events.whereType<HistoryGapEvent>().isNotEmpty);
      socket.receive({'op': 0, 's': 3, 't': 'GUILD_DELETE', 'd': deletion});
      await _drain();
      socket.receive(const {
        'op': 0,
        's': 4,
        't': 'READY_SUPPLEMENTAL',
        'd': {'lazy_private_channels': <Object?>[]},
      });
      await _drain();
      return events;
    }

    test('stays gone after the supplemental pass', () async {
      final events = await deleteThenSupplement(const {'id': _goneGuildId});

      expect(
        events.whereType<SpaceRemovedEvent>().map((event) => event.spaceId),
        [_goneGuildId],
      );
      final readded = events.whereType<WorkspaceDiffEvent>().expand(
        (event) => event.diff.spaces.map((space) => space.id),
      );
      expect(readded, isNot(contains(_goneGuildId)));
    });

    test('in an outage stays on the rail', () async {
      final events = await deleteThenSupplement(const {
        'id': _goneGuildId,
        'unavailable': true,
      });

      expect(events.whereType<SpaceRemovedEvent>(), isEmpty);
      final removed = events.whereType<WorkspaceDiffEvent>().expand(
        (event) => event.diff.removedSpaceIds,
      );
      expect(removed, isNot(contains(_goneGuildId)));
    });
  });

  test('a reconnect keeps the history the workspace already held', () async {
    final (repository, socket, events) = await connect();
    final page = await repository.loadChannelHistory(_keptChannelId);
    final held = page.history.messages.length;
    expect(held, 1);

    await reconnect(socket);
    socket.receive(_secondReady);
    await _waitFor(() => events.whereType<WorkspaceDiffEvent>().isNotEmpty);
    await _drain();

    // The renamed channel is still the account's channel, and the history
    // held for it survives the in-place hydration instead of being dropped
    // with a wholesale rebuild.
    final next = await repository.loadChannelHistory(_keptChannelId);
    expect(next.history.messages.map((message) => message.id), [_heldMessage]);
  });
}

final Map<String, Object?> _firstReady = _readyDispatch(1, _firstReadyPayload);

final Map<String, Object?> _firstReadyPayload = _readyPayload(
  guilds: [
    rawGuild(
      id: _guildId,
      name: 'Kept',
      channels: [
        rawChannel(
          id: _keptChannelId,
          name: 'general',
          lastMessageId: _ackedMessage,
        ),
      ],
    ),
    rawGuild(
      id: _goneGuildId,
      name: 'Gone',
      channels: [
        rawChannel(
          id: _deletedChannelId,
          name: 'doomed',
          lastMessageId: _ackedMessage,
        ),
      ],
    ),
  ],
);

final Map<String, Object?> _secondReady = _readyDispatch(
  2,
  _readyPayload(
    readStateVersion: 22,
    guilds: [
      rawGuild(
        id: _guildId,
        name: 'Kept',
        channels: [
          rawChannel(
            id: _keptChannelId,
            name: 'renamed',
            lastMessageId: _newestMessage,
          ),
          rawChannel(
            id: _newChannelId,
            name: 'fresh',
            lastMessageId: _ackedMessage,
          ),
        ],
      ),
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

/// A REST call this file did not plan for fails the test.
FakeDiscordTransport _transport() =>
    FakeDiscordTransport(
      fallback: (request) =>
          throw StateError('Unexpected REST call: ${request.uri.path}'),
    )..on(
      'GET',
      '/api/v9/channels/$_keptChannelId/messages',
      (_) => jsonResponse([
        rawMessage(
          id: _heldMessage,
          channelId: _keptChannelId,
          authorId: _recipientId,
          content: 'hello',
        ),
      ]),
    );
