import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _dmId = SessionHarness.dmChannelId;
const _friendId = SessionHarness.friendId;
const _strangerId = '100000000000000031';
const _newcomerId = '100000000000000032';

/// Newer than the DM, so above it in the list.
const _groupId = '400000000000000031';

/// Newer still, and only in READY_SUPPLEMENTAL.
const _lazyGroupId = '450000000000000031';

const _stranger = {
  'id': _strangerId,
  'username': 'stranger',
  'global_name': 'Stranger',
};

const _newcomer = {
  'id': _newcomerId,
  'username': 'newcomer',
  'global_name': 'Newcomer',
};

Finder _row(String id) => find.byKey(ValueKey('channel-$id'));

Finder _inRow(String id, String text) =>
    find.descendant(of: _row(id), matching: find.text(text));

/// The default READY, plus an unnamed group DM with the friend and a stranger.
Map<String, Object?> _readyWithGroup() {
  final ready = SessionHarness.defaultReady();
  ready['users'] = [...ready['users']! as List, _stranger];
  ready['private_channels'] = [
    ...ready['private_channels']! as List,
    {
      'id': _groupId,
      'type': 3,
      'name': null,
      'icon': null,
      'recipient_ids': [_friendId, _strangerId],
    },
  ];
  return ready;
}

/// The ids of those [ids] that are on screen, from top to bottom.
List<String> _rowsTopToBottom(WidgetTester tester, List<String> ids) {
  final shown = [
    for (final id in ids)
      if (_row(id).evaluate().isNotEmpty) id,
  ];
  return shown..sort(
    (left, right) => tester
        .getTopLeft(_row(left))
        .dy
        .compareTo(tester.getTopLeft(_row(right)).dy),
  );
}

void main() {
  testSession(
    'group DMs from READY and READY_SUPPLEMENTAL join the DM list in order',
    (tester, session) async {
      expect(_inRow(_groupId, 'Friend, Stranger'), findsOneWidget);
      expect(
        find.descendant(
          of: _row(_groupId),
          matching: find.byType(MemberAvatar),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _row(_groupId),
          matching: find.byKey(const ValueKey('group-dm-avatar-$_groupId')),
        ),
        findsOneWidget,
      );

      await session.dispatch('READY_SUPPLEMENTAL', {
        'lazy_private_channels': [
          {
            'id': _lazyGroupId,
            'type': 3,
            'name': 'Raid night',
            'icon': 'a1b2c3',
            'recipients': [_stranger],
          },
        ],
      });

      expect(_inRow(_lazyGroupId, 'Raid night'), findsOneWidget);
      expect(_rowsTopToBottom(tester, [_dmId, _groupId, _lazyGroupId]), [
        _lazyGroupId,
        _groupId,
        _dmId,
      ]);
    },
    ready: _readyWithGroup(),
  );

  testSession(
    'a group DM opens on its history and sends into it',
    (tester, session) async {
      session.transport.on(
        'POST',
        '/api/v9/channels/$_groupId/messages',
        (_) => jsonResponse(
          rawMessage(
            id: '900000000000000032',
            channelId: _groupId,
            authorId: SessionHarness.currentUserId,
            content: 'on my way',
          ),
        ),
      );

      await session.openChannel(_groupId, space: 'direct-messages');
      expect(session.messageRow('900000000000000031'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('message-composer')),
        'on my way',
      );
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('send-message')));
      await session.settle();

      final sent = session.transport.requests.where(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/api/v9/channels/$_groupId/messages',
      );
      expect(sent.single.json, containsPair('content', 'on my way'));
      expect(session.messageRow('900000000000000032'), findsOneWidget);
    },
    ready: _readyWithGroup(),
    routes: (transport) => transport.on(
      'GET',
      '/api/v9/channels/$_groupId/messages',
      (_) => jsonResponse([
        rawMessage(
          id: '900000000000000031',
          channelId: _groupId,
          authorId: _strangerId,
          content: 'who is in?',
        ),
      ]),
    ),
  );

  testSession('CHANNEL_CREATE and CHANNEL_DELETE change the list live', (
    tester,
    session,
  ) async {
    await session.dispatch('CHANNEL_CREATE', {
      'id': _groupId,
      'type': 3,
      'name': null,
      'recipients': [
        {'id': _friendId, 'username': 'friend', 'global_name': 'Friend'},
        _newcomer,
      ],
    });
    expect(_inRow(_groupId, 'Friend, Newcomer'), findsOneWidget);

    await session.dispatch('CHANNEL_DELETE', {'id': _groupId, 'type': 3});
    expect(_row(_groupId), findsNothing);
  });

  testSession(
    'a deleted group DM stays gone until a CHANNEL_CREATE brings it back',
    (tester, session) async {
      await session.dispatch('CHANNEL_DELETE', {'id': _groupId, 'type': 3});
      expect(_row(_groupId), findsNothing);

      // A late recipient event names a group the account has left.
      await session.dispatch('CHANNEL_RECIPIENT_ADD', {
        'channel_id': _groupId,
        'user': _newcomer,
      });
      expect(_row(_groupId), findsNothing);

      await session.dispatch('CHANNEL_CREATE', {
        'id': _groupId,
        'type': 3,
        'name': null,
        'recipients': [
          {'id': _friendId, 'username': 'friend', 'global_name': 'Friend'},
          _newcomer,
        ],
      });
      expect(_inRow(_groupId, 'Friend, Newcomer'), findsOneWidget);
    },
    ready: _readyWithGroup(),
  );

  testSession(
    'a closed DM comes back with the next message from the other side',
    (tester, session) async {
      expect(_row(_dmId), findsOneWidget);
      await session.dispatch('CHANNEL_DELETE', {'id': _dmId, 'type': 1});
      expect(_row(_dmId), findsNothing);

      await session.dispatch('MESSAGE_CREATE', {
        'id': '500000000000000031',
        'channel_id': _dmId,
        'channel_type': 1,
        'author': {
          'id': _friendId,
          'username': 'friend',
          'global_name': 'Friend',
        },
        'content': 'still there?',
        'timestamp': '2026-11-04T10:00:00.000000+00:00',
      });
      expect(_row(_dmId), findsOneWidget);
    },
  );

  testSession(
    'a recipient who joins or leaves renames an unnamed group',
    (tester, session) async {
      await session.dispatch('CHANNEL_RECIPIENT_ADD', {
        'channel_id': _groupId,
        'user': _newcomer,
      });
      expect(_inRow(_groupId, 'Friend, Stranger, Newcomer'), findsOneWidget);

      await session.dispatch('CHANNEL_RECIPIENT_REMOVE', {
        'channel_id': _groupId,
        'user': _stranger,
      });
      expect(_inRow(_groupId, 'Friend, Newcomer'), findsOneWidget);
    },
    ready: _readyWithGroup(),
  );

  testSession(
    'an offline launch keeps the group DM with its name',
    (tester, session) async {
      await session.relaunchUnreachable();

      expect(_inRow(_groupId, 'Friend, Stranger'), findsOneWidget);
    },
    ready: _readyWithGroup(),
    onDisk: true,
  );

  testSession(
    'a group with one other person stays a group, even when they leave',
    (tester, session) async {
      for (final id in [_duoId, _namedDuoId]) {
        expect(_groupAvatarIn(id), findsOneWidget);
        expect(
          find.descendant(of: _row(id), matching: find.byType(MemberAvatar)),
          findsNothing,
        );
      }
      expect(_inRow(_duoId, 'Stranger'), findsOneWidget);
      expect(_inRow(_namedDuoId, 'Duo'), findsOneWidget);

      await session.dispatch('CHANNEL_RECIPIENT_REMOVE', {
        'channel_id': _duoId,
        'user': _stranger,
      });

      expect(_groupAvatarIn(_duoId), findsOneWidget);
      expect(_inRow(_duoId, 'Unnamed group'), findsOneWidget);
    },
    ready: _readyWithDuos(),
  );
}

const _duoId = '400000000000000041';
const _namedDuoId = '400000000000000042';

Finder _groupAvatarIn(String id) => find.descendant(
  of: _row(id),
  matching: find.byKey(ValueKey('group-dm-avatar-$id')),
);

/// The default READY, plus two group DMs that each hold one other person.
Map<String, Object?> _readyWithDuos() {
  final ready = SessionHarness.defaultReady();
  ready['users'] = [...ready['users']! as List, _stranger];
  ready['private_channels'] = [
    ...ready['private_channels']! as List,
    {
      'id': _duoId,
      'type': 3,
      'name': null,
      'recipient_ids': [_strangerId],
    },
    {
      'id': _namedDuoId,
      'type': 3,
      'name': 'Duo',
      'icon': 'a1b2c3',
      'recipient_ids': [_strangerId],
    },
  ];
  return ready;
}
