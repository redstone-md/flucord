import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_member_list_ranges.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/guild_member_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<(DiscordDesktopChatRepository, MemoryDesktopWebSocket)>
  connect() async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final socket = MemoryDesktopWebSocket.etf();
    final gateway = DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      profile: _uncompressed,
      socketConnector: MemoryDesktopWebSocketConnector.answering(socket),
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

  const ready = {
    'op': 0,
    's': 1,
    't': 'READY',
    'd': {
      'session_id': 'session',
      'user': {'id': '111111111111111111'},
      'guilds': [
        {
          'id': 'guild',
          'roles': [
            {'id': 'guild', 'name': '@everyone', 'permissions': '1024'},
          ],
          'channels': [
            {'id': 'channel', 'type': 0, 'permission_overwrites': <Object?>[]},
          ],
        },
      ],
      'private_channels': <Object?>[],
    },
  };

  const memberListUpdate = {
    'op': 0,
    's': 2,
    't': 'GUILD_MEMBER_LIST_UPDATE',
    'd': {
      'guild_id': 'guild',
      'id': 'everyone',
      'member_count': 2,
      'online_count': 1,
      'groups': [
        {'id': 'online', 'count': 1},
      ],
      'ops': [
        {
          'op': 'SYNC',
          'range': [0, 1],
          'items': [
            {
              'group': {'id': 'online', 'count': 1},
            },
            {
              'member': {
                'user': {'id': '222222222222222222', 'username': 'Mira'},
                'roles': <Object?>[],
                'presence': {'status': 'online'},
              },
            },
          ],
        },
      ],
    },
  };

  test(
    'routes a roster dispatch into the store and the member cache',
    () async {
      final (repository, socket) = await connect();
      final events = <ChatRepositoryEvent>[];
      final lists = <GuildMemberList>[];
      repository.events.listen(events.add);
      repository.memberListUpdates.listen(lists.add);

      socket
        ..receive(ready)
        ..receive(memberListUpdate);
      await _waitFor(() => lists.isNotEmpty);

      expect(
        repository.memberListIdFor(guildId: 'guild', channelId: 'channel'),
        'everyone',
      );
      final list = repository.memberListFor(
        guildId: 'guild',
        listId: 'everyone',
      );
      expect(list?.rows, [
        const GuildMemberListGroupRow(groupId: 'online', count: 1),
        const GuildMemberListMemberRow('222222222222222222'),
      ]);
      expect(list?.memberCount, 2);
      expect(lists.single.version, 1);
      final upserted = events.whereType<MembersUpsertedEvent>().single;
      expect(upserted.members.single.id, '222222222222222222');
      expect(upserted.members.single.presence, Presence.online);
    },
  );

  test('subscribes and releases a channel range over opcode 37', () async {
    final (repository, socket) = await connect();
    socket.receive(ready);
    await _waitFor(() => socket.frames.any((frame) => frame['op'] == 37));

    repository.subscribeMemberRanges(
      guildId: 'guild',
      channelId: 'channel',
      ranges: DiscordMemberListRanges.initial,
    );
    final subscribed = _channelsOf(socket.frames.last);
    repository.unsubscribeMemberRanges(guildId: 'guild', channelId: 'channel');

    expect(subscribed, {
      'channel': [
        [0, 99],
      ],
    });
    expect(_channelsOf(socket.frames.last), isEmpty);
  });

  test('a replayed READY drops the rosters of the previous session', () async {
    final (repository, socket) = await connect();
    socket
      ..receive(ready)
      ..receive(memberListUpdate);
    await _waitFor(
      () =>
          repository.memberListFor(guildId: 'guild', listId: 'everyone') !=
          null,
    );

    socket.receive(ready);
    await _waitFor(
      () =>
          repository.memberListFor(guildId: 'guild', listId: 'everyone') ==
          null,
    );
  });
}

Object? _channelsOf(Map<String, Object?> frame) {
  final subscriptions =
      (frame['d']! as Map<String, Object?>)['subscriptions']!
          as Map<String, Object?>;
  return (subscriptions['guild']! as Map<String, Object?>)['channels'];
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
