import 'package:flucord/src/presentation/widgets/voice_room_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// The "Active now" column (FLUCORD-89) beside the friends panel, fed by the
// session: presence and voice state from the wire move its cards.

const _voiceId = '300000000000000050';

Map<String, Object?> _ready() {
  final ready = SessionHarness.defaultReady();
  ready['relationships'] = [
    {
      'id': SessionHarness.friendId,
      'type': 1,
      'user': {
        'id': SessionHarness.friendId,
        'username': 'friend',
        'global_name': 'Friend',
      },
    },
  ];
  final guild = (ready['guilds']! as List).first as Map<String, Object?>;
  guild['channels'] = [
    ...guild['channels']! as List,
    {...rawChannel(id: _voiceId, name: 'Lounge'), 'type': 2},
  ];
  return ready;
}

Future<void> _openFriends(WidgetTester tester, SessionHarness session) async {
  await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
  await session.settle();
  await tester.tap(find.byKey(const ValueKey('toggle-friends')));
  await session.settle();
}

final _card = find.byKey(
  const ValueKey('active-friend-${SessionHarness.friendId}'),
);

void main() {
  testSession('cards follow presence and voice state from the wire', (
    tester,
    session,
  ) async {
    await _openFriends(tester, session);
    expect(find.text('Active now'), findsOneWidget);
    expect(find.text("It's quiet for now"), findsOneWidget);

    await session.dispatch('PRESENCE_UPDATE', {
      'guild_id': SessionHarness.guildId,
      'status': 'online',
      'activities': [
        {'name': 'Dota 2', 'type': 0},
      ],
      'user': {'id': SessionHarness.friendId},
    });
    expect(
      find.descendant(of: _card, matching: find.text('Dota 2')),
      findsOneWidget,
    );

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
    expect(
      find.descendant(of: _card, matching: find.text('Lounge')),
      findsOneWidget,
    );

    expect(find.byType(VoiceRoomView), findsNothing);
    await tester.tap(_card);
    await session.settle();
    expect(find.byType(VoiceRoomView), findsOneWidget);
  }, ready: _ready());

  testSession(
    'a window too narrow for the column leaves it out',
    (tester, session) async {
      await _openFriends(tester, session);

      expect(find.byKey(const ValueKey('friends-panel')), findsOneWidget);
      expect(find.text('Active now'), findsNothing);
    },
    ready: _ready(),
    size: const Size(900, 800),
  );
}
