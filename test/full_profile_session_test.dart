import 'package:flucord/src/presentation/widgets/voice_room_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-91: the card opens the full profile window, which reads the
// profile route, the friend list and the voice seats from the session.

const _messageId = '900000000000000041';
const _voiceId = '300000000000000050';
const _playAndDayId = '200000000000000002';
const _lobbyId = '300000000000000060';

final _card = find.byKey(const ValueKey('profile-card'));
final _window = find.byKey(const ValueKey('full-profile'));

Finder _key(String key) => find.byKey(ValueKey(key));

/// A friend who is in The Forge and Play&day, with a voice channel in The
/// Forge.
Map<String, Object?> _ready() {
  final ready = SessionHarness.defaultReady();
  ready['relationships'] = [
    {
      'id': SessionHarness.friendId,
      'type': 1,
      'since': '2025-04-21T10:00:00+00:00',
      'user': {
        'id': SessionHarness.friendId,
        'username': 'friend',
        'global_name': 'Friend',
      },
    },
  ];
  final guilds = ready['guilds']! as List;
  final forge = guilds.first as Map<String, Object?>;
  forge['channels'] = [
    ...forge['channels']! as List,
    {...rawChannel(id: _voiceId, name: 'Lounge'), 'type': 2},
  ];
  forge['members'] = [
    {
      'user': {'id': SessionHarness.friendId, 'username': 'friend'},
      'roles': <Object?>[],
      'joined_at': '2026-01-29T10:00:00+00:00',
    },
  ];
  guilds.add(
    rawGuild(
      id: _playAndDayId,
      name: 'Play&day',
      channels: [rawChannel(id: _lobbyId, name: 'lobby')],
    ),
  );
  return ready;
}

/// Discord's profile route for the friend: a bio too long for the card, and
/// Play&day as a mutual server.
void _routeProfile(FakeDiscordTransport transport) => transport.on(
  'GET',
  '/api/v9/users/${SessionHarness.friendId}/profile',
  (_) => jsonResponse({
    'user': {'id': SessionHarness.friendId, 'username': 'friend'},
    'user_profile': {
      'bio': List.filled(30, 'Carry player, lobby after nine.').join(' '),
    },
    'mutual_guilds': [
      {'id': _playAndDayId, 'nick': 'Freezy'},
    ],
  }),
);

Future<void> _openCard(WidgetTester tester, SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
      id: _messageId,
      channelId: SessionHarness.channelId,
      guildId: SessionHarness.guildId,
      authorId: SessionHarness.friendId,
      content: 'hello',
    ),
  );
  await tester.tap(
    find.descendant(
      of: session.messageRow(_messageId),
      matching: _key('message-author-name'),
    ),
  );
  await session.settle();
  expect(_card, findsOneWidget);
}

Future<void> _openWindow(WidgetTester tester, SessionHarness session) async {
  await _openCard(tester, session);
  await tester.tap(_key('profile-card-name'));
  await session.settle();
}

void main() {
  for (final opener in [
    'profile-card-avatar',
    'profile-card-name',
    'profile-card-view-bio',
  ]) {
    testSession(
      '$opener opens the full profile in place of the card',
      (tester, session) async {
        await _openCard(tester, session);

        await tester.tap(_key(opener));
        await session.settle();

        expect(_card, findsNothing);
        expect(_window, findsOneWidget);
      },
      ready: _ready(),
      routes: _routeProfile,
    );
  }

  testSession(
    'the window shows when they joined and when you became friends',
    (tester, session) async {
      await _openWindow(tester, session);

      expect(
        find.descendant(
          of: _key('full-profile-member-since'),
          matching: find.textContaining('The Forge Jan 29, 2026'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('full-profile-friends-since'),
          matching: find.text('Apr 21, 2025'),
        ),
        findsOneWidget,
      );
    },
    ready: _ready(),
    routes: _routeProfile,
  );

  testSession(
    'Join opens the voice channel they sit in',
    (tester, session) async {
      await session.dispatch('VOICE_STATE_UPDATE', {
        'user_id': SessionHarness.friendId,
        'guild_id': SessionHarness.guildId,
        'channel_id': _voiceId,
        'session_id': 'friend-session',
        'self_mute': false,
        'self_deaf': false,
        'mute': false,
        'deaf': false,
        'self_stream': false,
        'self_video': false,
      });
      await _openWindow(tester, session);

      expect(find.byType(VoiceRoomView), findsNothing);
      await tester.tap(_key('voice-room-join'));
      await session.settle();

      expect(_window, findsNothing);
      expect(find.byType(VoiceRoomView), findsOneWidget);
    },
    ready: _ready(),
    routes: _routeProfile,
  );

  testSession(
    'a mutual server row opens the server',
    (tester, session) async {
      await _openWindow(tester, session);
      expect(_key('channel-$_lobbyId'), findsNothing);

      await tester.tap(_key('full-profile-tab-servers'));
      await session.settle();
      await tester.tap(_key('full-profile-server-$_playAndDayId'));
      await session.settle();

      expect(_window, findsNothing);
      expect(_key('channel-$_lobbyId'), findsOneWidget);
    },
    ready: _ready(),
    routes: _routeProfile,
  );

  testSession(
    'a connection link asks before it leaves the app',
    (tester, session) async {
      await _openWindow(tester, session);

      await tester.tap(_key('profile-connection-github'));
      await session.settle();

      expect(_key('leaving-site-dialog'), findsOneWidget);
    },
    ready: _ready(),
    routes: (transport) => transport.on(
      'GET',
      '/api/v9/users/${SessionHarness.friendId}/profile',
      (_) => jsonResponse({
        'user': {'id': SessionHarness.friendId, 'username': 'friend'},
        'connected_accounts': [
          {'type': 'github', 'id': '456', 'name': 'mira'},
        ],
      }),
    ),
  );
}
