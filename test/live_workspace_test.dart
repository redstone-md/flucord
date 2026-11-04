import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _guildId = SessionHarness.guildId;
const _generalId = SessionHarness.channelId;
const _randomId = SessionHarness.otherChannelId;
const _strangerId = '100000000000000003';
const _newDmId = '300000000000000010';
const _newChannelId = '300000000000000020';
const _threadId = '300000000000000021';
const _categoryId = '300000000000000022';
const _secondGuildId = '200000000000000002';
const _lobbyId = '300000000000000030';
const _messageId = '900000000000000001';

/// What `@everyone` is denied to hide a channel: view channel.
const _viewChannelBit = '1024';

/// A first DM's channel, as `CHANNEL_CREATE` carries it.
Map<String, Object?> _rawDirectMessage() => {
  'id': _newDmId,
  'type': 1,
  'last_message_id': null,
  'recipients': [
    {'id': _strangerId, 'username': 'stranger', 'global_name': 'Stranger'},
  ],
};

Map<String, Object?> _strangerMessage() => rawMessage(
  id: _messageId,
  channelId: _newDmId,
  authorId: _strangerId,
  content: 'hello there',
);

/// A guild channel as a channel dispatch carries it, with its guild named.
Map<String, Object?> _dispatchedChannel({
  required String id,
  required String name,
  List<Object?> overwrites = const [],
  String? parentId,
  int type = 0,
}) => {
  ...rawChannel(id: id, name: name),
  'guild_id': _guildId,
  'type': type,
  'parent_id': parentId,
  'permission_overwrites': overwrites,
};

Map<String, Object?> _thread({bool archived = false}) => {
  'id': _threadId,
  'type': 11,
  'name': 'a thread',
  'guild_id': _guildId,
  'parent_id': _generalId,
  'thread_metadata': {'archived': archived, 'locked': false},
};

Map<String, Object?> _rawMember({
  String? nick,
  List<String> roles = const [],
}) => {
  'guild_id': _guildId,
  'user': {'id': _strangerId, 'username': 'stranger'},
  'nick': nick,
  'roles': roles,
};

Map<String, Object?> _secondGuild({String name = 'The Annex'}) => rawGuild(
  id: _secondGuildId,
  name: name,
  channels: [rawChannel(id: _lobbyId, name: 'lobby')],
);

Finder _channelRow(String id) => find.byKey(ValueKey('channel-$id'));
Finder _railButton(String id) => find.byKey(ValueKey('space-$id'));
Finder _memberRow(String id) => find.byKey(ValueKey('member-row-$id'));

/// A row's name. The weight of its text is how a row says it is unread.
FontWeight? _rowWeight(WidgetTester tester, String id, String name) => tester
    .widget<Text>(
      find.descendant(of: _channelRow(id), matching: find.text(name)),
    )
    .style
    ?.fontWeight;

const _readStatePath = '/api/v9/guilds/$_secondGuildId/read-state';

/// A new guild asks for its read state. A refused ask is an uncaught error
/// today, which fails a test, so these tests answer it.
void _routeReadState(SessionHarness session) => session.transport.on(
  'GET',
  _readStatePath,
  (_) => jsonResponse(<String, Object?>{}),
);

/// Whether the channel's history went out, which is what opening it does.
bool _historyAsked(SessionHarness session, String channelId) =>
    session.transport.requests.any(
      (request) => request.uri.path == '/api/v9/channels/$channelId/messages',
    );

void main() {
  group('direct messages', () {
    testSession('a first DM shows its row and its unread marker at once', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);

      await session.dispatch('CHANNEL_CREATE', _rawDirectMessage());
      await session.dispatch('MESSAGE_CREATE', _strangerMessage());

      // The rail shows it while the account is looking at another server. A
      // DM message counts as a mention, as in Discord.
      expect(
        find.bySemanticsLabel('Direct Messages, 1 mention'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
      await session.settle();

      expect(_channelRow(_newDmId), findsOneWidget);
      expect(_rowWeight(tester, _newDmId, 'Stranger'), FontWeight.w500);
    });

    testSession('a message right behind its new channel is not lost', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);

      // Both in one frame, as a socket read delivers them.
      await session.dispatch(
        'CHANNEL_CREATE',
        _rawDirectMessage(),
        settle: false,
      );
      await session.dispatch('MESSAGE_CREATE', _strangerMessage());

      expect(
        find.bySemanticsLabel('Direct Messages, 1 mention'),
        findsOneWidget,
      );
    });

    testSession('a first DM with no CHANNEL_CREATE still shows', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);

      await session.dispatch('MESSAGE_CREATE', _strangerMessage());

      expect(
        find.bySemanticsLabel('Direct Messages, 1 mention'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
      await session.settle();
      expect(_channelRow(_newDmId), findsOneWidget);
    });

    testSession('a new DM goes to the top of the list', (
      tester,
      session,
    ) async {
      await session.dispatch('CHANNEL_CREATE', _rawDirectMessage());

      expect(
        tester.getTopLeft(_channelRow(_newDmId)).dy,
        lessThan(tester.getTopLeft(_channelRow(SessionHarness.dmChannelId)).dy),
      );
    });

    testSession('a re-identify vouches for the new DM in its private cursor', (
      tester,
      session,
    ) async {
      await session.dispatch('CHANNEL_CREATE', _rawDirectMessage());
      await session.dispatch('MESSAGE_ACK', {
        'channel_id': _newDmId,
        'message_id': _messageId,
        'version': 2,
      });

      session.socket.receive({'op': 9, 'd': false});
      await session.settle();

      final identify = session.socket.frames.lastWhere((f) => f['op'] == 2);
      final clientState = (identify['d']! as Map)['client_state']! as Map;
      expect(clientState['private_channels_version'], _messageId);
    });
  });

  group('channels', () {
    testSession('a new channel shows in the sidebar', (tester, session) async {
      await session.openChannel(_generalId);

      await session.dispatch(
        'CHANNEL_CREATE',
        _dispatchedChannel(id: _newChannelId, name: 'announcements'),
      );

      expect(_channelRow(_newChannelId), findsOneWidget);
    });

    testSession('a rename shows and keeps the unread marker', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: _messageId,
          channelId: _randomId,
          guildId: _guildId,
          authorId: SessionHarness.friendId,
          content: 'unread here',
        ),
      );

      await session.dispatch(
        'CHANNEL_UPDATE',
        _dispatchedChannel(id: _randomId, name: 'renamed'),
      );

      expect(_rowWeight(tester, _randomId, 'renamed'), FontWeight.w500);
    });

    testSession(
      'a permission change hides the channel and brings it back',
      (tester, session) async {
        await session.openChannel(_generalId);

        await session.dispatch(
          'CHANNEL_UPDATE',
          _dispatchedChannel(
            id: _randomId,
            name: 'random',
            overwrites: [
              {
                'id': _guildId,
                'type': 0,
                'allow': '0',
                'deny': _viewChannelBit,
              },
            ],
          ),
        );
        expect(_channelRow(_randomId), findsNothing);

        await session.dispatch(
          'CHANNEL_UPDATE',
          _dispatchedChannel(id: _randomId, name: 'random'),
        );
        expect(_channelRow(_randomId), findsOneWidget);
      },
      ready: () {
        // The account's own membership, or the client cannot judge permissions.
        final ready = SessionHarness.defaultReady();
        return {
          ...ready,
          'users': [
            ...ready['users']! as List<Object?>,
            {'id': SessionHarness.currentUserId, 'username': 'me'},
          ],
          'merged_members': [
            [
              {'user_id': SessionHarness.currentUserId, 'roles': <String>[]},
            ],
          ],
        };
      }(),
    );

    testSession('deleting the open channel moves the user to another', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);

      await session.dispatch('CHANNEL_DELETE', {
        'id': _generalId,
        'type': 0,
        'guild_id': _guildId,
      });

      expect(_channelRow(_generalId), findsNothing);
      expect(_historyAsked(session, _randomId), isTrue);
    });

    testSession('a new category and its channel show, and it can go again', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);

      await session.dispatch(
        'CHANNEL_CREATE',
        _dispatchedChannel(id: _categoryId, name: 'ops', type: 4),
      );
      await session.dispatch(
        'CHANNEL_CREATE',
        _dispatchedChannel(
          id: _newChannelId,
          name: 'alerts',
          parentId: _categoryId,
        ),
      );
      expect(find.text('OPS'), findsOneWidget);
      expect(_channelRow(_newChannelId), findsOneWidget);

      await session.dispatch('CHANNEL_DELETE', {
        'id': _categoryId,
        'type': 4,
        'guild_id': _guildId,
      });
      expect(find.text('OPS'), findsNothing);
      expect(_channelRow(_newChannelId), findsOneWidget);
    });
  });

  group('threads', () {
    testSession('a new thread shows, and leaves when it is archived', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);

      await session.dispatch('THREAD_CREATE', _thread());
      expect(_channelRow(_threadId), findsOneWidget);

      await session.dispatch('THREAD_UPDATE', _thread(archived: true));
      expect(_channelRow(_threadId), findsNothing);
    });

    testSession('a deleted thread leaves the sidebar', (tester, session) async {
      await session.openChannel(_generalId);
      await session.dispatch('THREAD_CREATE', _thread());

      await session.dispatch('THREAD_DELETE', {
        'id': _threadId,
        'type': 11,
        'guild_id': _guildId,
        'parent_id': _generalId,
      });

      expect(_channelRow(_threadId), findsNothing);
    });
  });

  group('guilds', () {
    testSession('a new guild joins the rail, usable and subscribed', (
      tester,
      session,
    ) async {
      _routeReadState(session);
      await session.dispatch('GUILD_CREATE', _secondGuild());

      expect(_railButton(_secondGuildId), findsOneWidget);
      final subscribed = session.socket.frames.where((f) => f['op'] == 37);
      expect(
        subscribed.map((f) => (f['d']! as Map)['subscriptions'] as Map),
        contains(contains(_secondGuildId)),
      );

      await session.openChannel(_lobbyId, space: _secondGuildId);
      expect(_historyAsked(session, _lobbyId), isTrue);
    });

    testSession('a guild asks for its read state only the first time', (
      tester,
      session,
    ) async {
      _routeReadState(session);
      await session.dispatch('GUILD_CREATE', _secondGuild());
      await session.dispatch('GUILD_CREATE', _secondGuild());

      expect(
        session.transport.requests.where((r) => r.uri.path == _readStatePath),
        hasLength(1),
      );
    });

    testSession(
      'an unavailable guild does not join the rail until it has its channels',
      (tester, session) async {
        _routeReadState(session);
        await session.dispatch('GUILD_CREATE', {
          'id': _secondGuildId,
          'unavailable': true,
        });
        expect(_railButton(_secondGuildId), findsNothing);

        await session.dispatch('GUILD_CREATE', _secondGuild());
        expect(_railButton(_secondGuildId), findsOneWidget);
      },
    );

    testSession(
      'a repeated GUILD_CREATE keeps the rail order and the unread marker',
      (tester, session) async {
        await session.openChannel(_generalId);
        await session.dispatch(
          'MESSAGE_CREATE',
          rawMessage(
            id: _messageId,
            channelId: _randomId,
            guildId: _guildId,
            authorId: SessionHarness.friendId,
            content: 'unread here',
          ),
        );

        await session.dispatch(
          'GUILD_CREATE',
          rawGuild(
            id: _guildId,
            name: 'The Forge',
            channels: [
              rawChannel(id: _generalId, name: 'general'),
              rawChannel(id: _randomId, name: 'random'),
            ],
          ),
        );

        expect(
          tester.getTopLeft(_railButton(_guildId)).dy,
          lessThan(tester.getTopLeft(_railButton(_secondGuildId)).dy),
        );
        expect(_rowWeight(tester, _randomId, 'random'), FontWeight.w500);
      },
      ready: {
        ...SessionHarness.defaultReady(),
        'guilds': [
          ...SessionHarness.defaultReady()['guilds']! as List<Object?>,
          _secondGuild(),
        ],
      },
    );

    testSession(
      'a renamed guild keeps its place on the rail',
      (tester, session) async {
        await session.dispatch('GUILD_UPDATE', {
          'id': _guildId,
          'name': 'The New Forge',
        });

        expect(find.bySemanticsLabel('The New Forge'), findsOneWidget);
        expect(
          tester.getTopLeft(_railButton(_guildId)).dy,
          lessThan(tester.getTopLeft(_railButton(_secondGuildId)).dy),
        );
      },
      ready: {
        ...SessionHarness.defaultReady(),
        'guilds': [
          ...SessionHarness.defaultReady()['guilds']! as List<Object?>,
          _secondGuild(),
        ],
      },
    );

    testSession('a removed guild leaves the rail and takes the user home', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);

      await session.dispatch('GUILD_DELETE', {'id': _guildId});

      expect(_railButton(_guildId), findsNothing);
      expect(_channelRow(_generalId), findsNothing);
      expect(_channelRow(SessionHarness.dmChannelId), findsOneWidget);
      expect(_historyAsked(session, SessionHarness.dmChannelId), isTrue);
    });

    testSession('an outage is not a removal', (tester, session) async {
      await session.openChannel(_generalId);

      await session.dispatch('GUILD_DELETE', {
        'id': _guildId,
        'unavailable': true,
      });

      expect(_railButton(_guildId), findsOneWidget);
      expect(_channelRow(_generalId), findsOneWidget);
    });
  });

  group('members', () {
    testSession('a member added, renamed and removed changes the list', (
      tester,
      session,
    ) async {
      await session.openChannel(_generalId);

      await session.dispatch('GUILD_MEMBER_ADD', _rawMember());
      expect(_memberRow(_strangerId), findsOneWidget);

      await session.dispatch('GUILD_MEMBER_UPDATE', _rawMember(nick: 'Nick'));
      expect(
        find.descendant(
          of: _memberRow(_strangerId),
          matching: find.text('Nick'),
        ),
        findsOneWidget,
      );

      await session.dispatch('GUILD_MEMBER_REMOVE', _rawMember());
      expect(_memberRow(_strangerId), findsNothing);
    });

    const roleId = '400000000000000001';
    testSession(
      'a member update shows the role by name',
      (tester, session) async {
        await session.openChannel(_generalId);

        await session.dispatch(
          'GUILD_MEMBER_UPDATE',
          _rawMember(roles: [roleId]),
        );

        // A member row has no role line, so the role shows on the profile.
        await tester.tap(_memberRow(_strangerId));
        await tester.pumpAndSettle();

        expect(find.text('Moderator'), findsOneWidget);
      },
      ready: {
        ...SessionHarness.defaultReady(),
        'guilds': [
          {
            ...rawGuild(
              id: _guildId,
              name: 'The Forge',
              channels: [rawChannel(id: _generalId, name: 'general')],
            ),
            'roles': [
              {'id': _guildId, 'name': '@everyone', 'permissions': '1024'},
              {
                'id': roleId,
                'name': 'Moderator',
                'position': 1,
                'permissions': '0',
              },
            ],
          },
        ],
      },
    );

    testSession('a live channel reads the roster the server names for it', (
      tester,
      session,
    ) async {
      await session.dispatch('CHANNEL_CREATE', {
        ..._dispatchedChannel(id: _newChannelId, name: 'private'),
        'member_list_id': 'list-of-the-new-channel',
      });
      await session.openChannel(_newChannelId);

      await session.dispatch('GUILD_MEMBER_LIST_UPDATE', {
        'guild_id': _guildId,
        'id': 'list-of-the-new-channel',
        'member_count': 1,
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
                  'user': {'id': _strangerId, 'username': 'stranger'},
                  'roles': <Object?>[],
                  'presence': {'status': 'online'},
                },
              },
            ],
          },
        ],
      });

      // Only the server's roster has this group. The local fallback groups by role.
      expect(find.text('Online - 1'), findsOneWidget);
      expect(_memberRow(_strangerId), findsOneWidget);
    });
  });

  group('pins', () {
    const pinsPath = '/api/v9/channels/$_generalId/messages/pins';
    Map<String, Object?> pinsPage(String content) => {
      'items': [
        {
          'message': rawMessage(
            id: _messageId,
            channelId: _generalId,
            guildId: _guildId,
            authorId: SessionHarness.friendId,
            content: content,
          ),
        },
      ],
    };

    testSession(
      'CHANNEL_PINS_UPDATE refreshes an open pins panel',
      (tester, session) async {
        await session.openChannel(_generalId);
        await tester.tap(find.byKey(const ValueKey('toggle-pins')));
        await session.settle();
        expect(find.textContaining('the old pin'), findsOneWidget);

        session.transport.on(
          'GET',
          pinsPath,
          (_) => jsonResponse(pinsPage('the new pin')),
        );
        await session.dispatch('CHANNEL_PINS_UPDATE', {
          'channel_id': _generalId,
          'guild_id': _guildId,
          'last_pin_timestamp': '2026-07-25T10:00:00+00:00',
        });

        expect(find.textContaining('the new pin'), findsOneWidget);
        expect(find.textContaining('the old pin'), findsNothing);
      },
      routes: (transport) => transport.on(
        'GET',
        pinsPath,
        (_) => jsonResponse(pinsPage('the old pin')),
      ),
    );
  });
}
