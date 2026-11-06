import 'package:flucord/src/presentation/widgets/chat_header.dart';
import 'package:flucord/src/presentation/widgets/destructive_confirmation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _meId = SessionHarness.currentUserId;
const _friendId = SessionHarness.friendId;
const _dmId = SessionHarness.dmChannelId;
const _strangerId = '100000000000000031';
const _newcomerId = '100000000000000032';
const _groupId = '400000000000000031';

const _friend = {
  'id': _friendId,
  'username': 'friend',
  'global_name': 'Friend',
};
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

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _row(String id) => _key('channel-$id');

Finder _inRow(String id, String text) =>
    find.descendant(of: _row(id), matching: find.text(text));

Finder _inHeader(String text) =>
    find.descendant(of: find.byType(ChatHeader), matching: find.text(text));

/// The requests that went out as [method] on [path].
List<RecordedRequest> _sent(
  SessionHarness session,
  String method,
  String path,
) => [
  for (final request in session.transport.requests)
    if (request.method == method && request.uri.path == path) request,
];

/// A group DM as Discord answers or announces it.
Map<String, Object?> _rawGroup({
  String? name,
  String? icon,
  String ownerId = _meId,
  List<Map<String, Object?>> recipients = const [_friend, _stranger],
}) => {
  'id': _groupId,
  'type': 3,
  'name': name,
  'icon': icon,
  'owner_id': ownerId,
  'recipients': recipients,
};

/// READY with three friends: the default one, a stranger and a newcomer.
Map<String, Object?> _readyWithFriends({
  bool withGroup = false,
  String? owner,
}) {
  final ready = SessionHarness.defaultReady();
  ready['users'] = [...ready['users']! as List, _stranger, _newcomer];
  ready['relationships'] = [
    for (final user in [_friend, _stranger, _newcomer])
      {'id': user['id'], 'type': 1, 'user': user},
  ];
  if (withGroup) {
    ready['private_channels'] = [
      ...ready['private_channels']! as List,
      {
        'id': _groupId,
        'type': 3,
        'name': 'Raid night',
        'icon': 'a1b2c3',
        'owner_id': owner ?? _meId,
        'recipient_ids': [_friendId, _strangerId],
      },
    ];
  }
  return ready;
}

Future<void> _openGroup(SessionHarness session) =>
    session.openChannel(_groupId, space: 'direct-messages');

void main() {
  testSession(
    'starts a group DM with two friends from the DM list',
    (tester, session) async {
      await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
      await session.settle();
      await tester.tap(_key('new-group-direct-message'));
      await session.settle();

      await tester.tap(_key('friend-picker-$_friendId'));
      await tester.tap(_key('friend-picker-$_strangerId'));
      await tester.pump();
      await tester.tap(_key('friend-picker-confirm'));
      await session.settle();

      final created = _sent(session, 'POST', '/api/v9/users/@me/channels');
      expect(
        (created.single.json! as Map)['recipients'],
        unorderedEquals([_friendId, _strangerId]),
      );
      expect(_inRow(_groupId, 'Friend, Stranger'), findsOneWidget);
      expect(_inHeader('Friend, Stranger'), findsOneWidget);
    },
    ready: _readyWithFriends(),
    routes: (transport) => transport.on(
      'POST',
      '/api/v9/users/@me/channels',
      (_) => jsonResponse(_rawGroup()),
    ),
  );
  testSession(
    'leaving a group asks first, then takes it off the list',
    (tester, session) async {
      await _openGroup(session);

      await tester.tap(_key('close-direct-message-$_groupId'));
      await session.settle();
      await tester.tap(find.text('Cancel'));
      await session.settle();
      expect(_sent(session, 'DELETE', '/api/v9/channels/$_groupId'), isEmpty);
      expect(_row(_groupId), findsOneWidget);

      await tester.tap(_key('close-direct-message-$_groupId'));
      await session.settle();
      expect(find.text("Leave 'Raid night'"), findsOneWidget);
      await tester.tap(find.byKey(destructiveConfirmKey));
      await session.settle();

      expect(
        _sent(session, 'DELETE', '/api/v9/channels/$_groupId'),
        hasLength(1),
      );
      expect(_row(_groupId), findsNothing);
    },
    ready: _readyWithFriends(withGroup: true),
    routes: (transport) => transport.on(
      'DELETE',
      '/api/v9/channels/$_groupId',
      (_) => jsonResponse(_rawGroup(name: 'Raid night')),
    ),
  );

  testSession(
    'a closed DM leaves the list until a new message arrives',
    (tester, session) async {
      await session.openChannel(_dmId, space: 'direct-messages');

      await tester.tap(_key('close-direct-message-$_dmId'));
      await session.settle();

      expect(_sent(session, 'DELETE', '/api/v9/channels/$_dmId'), hasLength(1));
      expect(_row(_dmId), findsNothing);

      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: '500000000000000041',
          channelId: _dmId,
          authorId: _friendId,
          content: 'still there?',
        )..['channel_type'] = 1,
      );
      expect(_row(_dmId), findsOneWidget);
    },
    routes: (transport) => transport.on(
      'DELETE',
      '/api/v9/channels/$_dmId',
      (_) => jsonResponse({
        'id': _dmId,
        'type': 1,
        'recipients': [_friend],
      }),
    ),
  );
  testSession(
    'adds a friend to a group from its header',
    (tester, session) async {
      await _openGroup(session);

      await tester.tap(_key('group-dm-add'));
      await session.settle();
      expect(_key('friend-picker-$_friendId'), findsNothing);
      await tester.tap(_key('friend-picker-$_newcomerId'));
      await tester.pump();
      await tester.tap(_key('friend-picker-confirm'));
      await session.settle();

      expect(
        _sent(
          session,
          'PUT',
          '/api/v9/channels/$_groupId/recipients/$_newcomerId',
        ),
        hasLength(1),
      );
    },
    ready: _readyWithFriends(withGroup: true),
    routes: (transport) => transport.on(
      'PUT',
      '/api/v9/channels/$_groupId/recipients/$_newcomerId',
      (_) => jsonResponse(null, statusCode: 204),
    ),
  );

  testSession(
    'the owner removes somebody from the group settings',
    (tester, session) async {
      await _openGroup(session);
      await tester.tap(_key('group-dm-settings'));
      await session.settle();

      await tester.tap(_key('group-dm-remove-$_strangerId'));
      await session.settle();
      expect(
        _sent(
          session,
          'DELETE',
          '/api/v9/channels/$_groupId/recipients/$_strangerId',
        ),
        hasLength(1),
      );

      await session.dispatch('CHANNEL_RECIPIENT_REMOVE', {
        'channel_id': _groupId,
        'user': _stranger,
      });
      expect(_key('group-dm-member-$_strangerId'), findsNothing);
      expect(_key('group-dm-member-$_friendId'), findsOneWidget);
    },
    ready: _readyWithFriends(withGroup: true),
    routes: (transport) => transport.on(
      'DELETE',
      '/api/v9/channels/$_groupId/recipients/$_strangerId',
      (_) => jsonResponse(null, statusCode: 204),
    ),
  );

  testSession(
    'only the owner is offered to remove people',
    (tester, session) async {
      await _openGroup(session);
      await tester.tap(_key('group-dm-settings'));
      await session.settle();

      expect(_key('group-dm-member-$_strangerId'), findsOneWidget);
      expect(_key('group-dm-remove-$_strangerId'), findsNothing);
    },
    ready: _readyWithFriends(withGroup: true, owner: _friendId),
  );

  testSession(
    'renames a group and removes its icon',
    (tester, session) async {
      await _openGroup(session);
      await tester.tap(_key('group-dm-settings'));
      await session.settle();

      await tester.tap(_key('group-dm-remove-icon'));
      await session.settle();
      await tester.enterText(_key('group-dm-name'), 'Boss fight');
      await tester.tap(_key('group-dm-save'));
      await session.settle();

      final edits = [
        for (final request in _sent(
          session,
          'PATCH',
          '/api/v9/channels/$_groupId',
        ))
          request.json,
      ];
      expect(edits, [
        {'icon': null},
        {'name': 'Boss fight'},
      ]);
      expect(_key('group-dm-name'), findsNothing);
      expect(_inRow(_groupId, 'Boss fight'), findsOneWidget);
      expect(_inHeader('Boss fight'), findsOneWidget);
    },
    ready: _readyWithFriends(withGroup: true),
    routes: (transport) =>
        transport.on('PATCH', '/api/v9/channels/$_groupId', (request) {
          final body = request.json! as Map;
          return jsonResponse(
            _rawGroup(name: body['name'] as String? ?? 'Raid night'),
          );
        }),
  );

  testSession(
    'a rename and a new member from the gateway change the list and header',
    (tester, session) async {
      await _openGroup(session);

      await session.dispatch(
        'CHANNEL_UPDATE',
        _rawGroup(name: 'Boss fight', ownerId: _friendId),
      );
      expect(_inRow(_groupId, 'Boss fight'), findsOneWidget);
      expect(_inHeader('Boss fight'), findsOneWidget);

      await session.dispatch('CHANNEL_RECIPIENT_ADD', {
        'channel_id': _groupId,
        'user': _newcomer,
      });
      await tester.tap(_key('group-dm-settings'));
      await session.settle();
      expect(_key('group-dm-member-$_newcomerId'), findsOneWidget);
      // The update made the friend the owner.
      expect(_key('group-dm-remove-$_newcomerId'), findsNothing);
    },
    ready: _readyWithFriends(withGroup: true),
  );
}
