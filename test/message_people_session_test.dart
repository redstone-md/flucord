import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';

final _profileCard = find.byKey(const ValueKey('member-profile-popover'));

Future<void> _openWithMessageFromFriend(SessionHarness session) async {
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
}

const _adminRole = '400000000000000001';
const _plainRole = '400000000000000002';
const _lowRole = '400000000000000003';

const _adminColor = Color(0xFFE91E63);
const _lowColor = Color(0xFF2ECC71);

/// The default READY, with a guild that has coloured roles and one with none.
Map<String, Object?> _readyWithRoles() {
  final ready = SessionHarness.defaultReady();
  final guild = (ready['guilds']! as List).first as Map<String, Object?>;
  guild['roles'] = [
    ...guild['roles']! as List,
    {'id': _adminRole, 'name': 'Admin', 'color': 0xE91E63, 'position': 3},
    {'id': _plainRole, 'name': 'Plain', 'color': 0, 'position': 5},
    {'id': _lowRole, 'name': 'Low', 'color': 0x2ECC71, 'position': 1},
  ];
  return ready;
}

/// What the author's name is drawn in, on the row of [_messageId].
Color? _authorColor(WidgetTester tester, SessionHarness session) => tester
    .widget<Text>(
      find.descendant(
        of: find.descendant(
          of: session.messageRow(_messageId),
          matching: find.byKey(const ValueKey('message-author-name')),
        ),
        matching: find.byType(Text),
      ),
    )
    .style
    ?.color;

Future<void> _messageFromAuthorWithRoles(
  SessionHarness session,
  List<String> roles,
) async {
  await session.openChannel(SessionHarness.channelId);
  await session.dispatch('MESSAGE_CREATE', {
    ...rawMessage(
      id: _messageId,
      channelId: SessionHarness.channelId,
      guildId: SessionHarness.guildId,
      authorId: SessionHarness.friendId,
      content: 'hello',
    ),
    'member': {'roles': roles},
  });
}

void main() {
  group('an author\'s name', () {
    testSession('takes the colour of their role', (tester, session) async {
      await _messageFromAuthorWithRoles(session, [_adminRole]);

      expect(_authorColor(tester, session), _adminColor);
    }, ready: _readyWithRoles());

    testSession(
      'takes the highest role that has a colour',
      (tester, session) async {
        await _messageFromAuthorWithRoles(session, [
          _lowRole,
          _plainRole,
          _adminRole,
        ]);

        expect(_authorColor(tester, session), _adminColor);
      },
      ready: _readyWithRoles(),
    );

    testSession(
      'keeps the normal text colour with no coloured role',
      (tester, session) async {
        await _messageFromAuthorWithRoles(session, [_plainRole]);

        expect(_authorColor(tester, session), isNull);
      },
      ready: _readyWithRoles(),
    );

    testSession(
      'colours in from a member reply when a history page names no roles',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        final asked = session.socket.frames.where(
          (frame) => frame['op'] == 8,
        );
        expect(asked, hasLength(1));
        expect((asked.single['d']! as Map)['user_ids'], [
          SessionHarness.friendId,
        ]);
        expect((asked.single['d']! as Map)['guild_id'], SessionHarness.guildId);
        expect(_authorColor(tester, session), isNull);

        await session.dispatch('GUILD_MEMBERS_CHUNK', {
          'guild_id': SessionHarness.guildId,
          'members': [
            {
              'user': {'id': SessionHarness.friendId, 'username': 'friend'},
              'roles': [_lowRole],
            },
          ],
        });

        expect(_authorColor(tester, session), _lowColor);
      },
      ready: _readyWithRoles(),
      routes: (transport) => transport.on(
        'GET',
        '/api/v9/channels/${SessionHarness.channelId}/messages',
        (_) => jsonResponse([
          rawMessage(
            id: _messageId,
            channelId: SessionHarness.channelId,
            authorId: SessionHarness.friendId,
            content: 'from history',
          ),
        ]),
      ),
    );

    testSession('shows their nickname in that server', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch('MESSAGE_CREATE', {
        ...rawMessage(
          id: _messageId,
          channelId: SessionHarness.channelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.friendId,
          content: 'hello',
        ),
        'member': {'nick': 'Forge Friend', 'roles': <String>[]},
      });

      expect(
        find.descendant(
          of: session.messageRow(_messageId),
          matching: find.text('Forge Friend'),
        ),
        findsOneWidget,
      );
    });

    testSession(
      'asks about each author once',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await tester.tap(
          find.byKey(const ValueKey('channel-${SessionHarness.otherChannelId}')),
        );
        await session.settle();
        await tester.tap(
          find.byKey(const ValueKey('channel-${SessionHarness.channelId}')),
        );
        await session.settle();

        expect(session.socket.frames.where((f) => f['op'] == 8), hasLength(1));
      },
      ready: _readyWithRoles(),
      routes: (transport) {
        for (final (index, channel) in [
          SessionHarness.channelId,
          SessionHarness.otherChannelId,
        ].indexed) {
          transport.on(
            'GET',
            '/api/v9/channels/$channel/messages',
            (_) => jsonResponse([
              rawMessage(
                id: '90000000000000001$index',
                channelId: channel,
                authorId: SessionHarness.friendId,
                content: 'from history',
              ),
            ]),
          );
        }
      },
    );
  });

  group('clicking an author', () {
    testSession('on the name opens their profile', (tester, session) async {
      await _openWithMessageFromFriend(session);

      await tester.tap(
        find.descendant(
          of: session.messageRow(_messageId),
          matching: find.byKey(const ValueKey('message-author-name')),
        ),
      );
      await session.settle();

      expect(_profileCard, findsOneWidget);
    });

    testSession('on the avatar opens their profile', (tester, session) async {
      await _openWithMessageFromFriend(session);

      await tester.tap(
        find.descendant(
          of: session.messageRow(_messageId),
          matching: find.byKey(const ValueKey('message-author-avatar')),
        ),
      );
      await session.settle();

      expect(_profileCard, findsOneWidget);
    });
  });
}
