import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// The DM list follows the latest activity (FLUCORD-120): each conversation
// counts by the newer of its last message id and its channel id, newest on top.

const _dmId = SessionHarness.dmChannelId;
const _friendId = SessionHarness.friendId;

/// Newer than the DM, so above it while neither has a message.
const _groupId = '400000000000000031';

/// Between the two, for a conversation created during the session.
const _newDmId = '350000000000000031';

const _friend = {
  'id': _friendId,
  'username': 'friend',
  'global_name': 'Friend',
};

Finder _row(String id) => find.byKey(ValueKey('channel-$id'));

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

/// The default READY, plus a group DM nobody has written in.
Map<String, Object?> _readyWithGroup({
  String? dmLastMessageId,
  String? dmAckedId,
}) {
  final ready = SessionHarness.defaultReady();
  final dm = (ready['private_channels']! as List).single as Map;
  if (dmLastMessageId != null) dm['last_message_id'] = dmLastMessageId;
  ready['private_channels'] = [
    dm,
    {
      'id': _groupId,
      'type': 3,
      'name': 'Raid night',
      'recipient_ids': [_friendId],
    },
  ];
  if (dmAckedId != null) {
    ready['read_state'] = {
      'version': 1,
      'partial': false,
      'entries': [
        {'id': _dmId, 'last_message_id': dmAckedId, 'mention_count': 0},
      ],
    };
  }
  return ready;
}

void main() {
  testSession(
    'a message from the other side moves its DM to the top',
    (tester, session) async {
      expect(_rowsTopToBottom(tester, [_dmId, _groupId]), [_groupId, _dmId]);

      await session.dispatch('MESSAGE_CREATE', {
        'id': '500000000000000031',
        'channel_id': _dmId,
        'channel_type': 1,
        'author': _friend,
        'content': 'still there?',
        'timestamp': '2026-11-04T10:00:00.000000+00:00',
      });

      expect(_rowsTopToBottom(tester, [_dmId, _groupId]), [_dmId, _groupId]);
    },
    ready: _readyWithGroup(),
  );

  testSession(
    'a message sent into a DM moves it to the top, and it stays open',
    (tester, session) async {
      session.transport.on(
        'POST',
        '/api/v9/channels/$_dmId/messages',
        (_) => jsonResponse(
          rawMessage(
            id: '500000000000000032',
            channelId: _dmId,
            authorId: SessionHarness.currentUserId,
            content: 'on my way',
          ),
        ),
      );
      await session.openChannel(_dmId, space: 'direct-messages');
      expect(_rowsTopToBottom(tester, [_dmId, _groupId]), [_groupId, _dmId]);

      await tester.enterText(
        find.byKey(const ValueKey('message-composer')),
        'on my way',
      );
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('send-message')));
      await session.settle();

      expect(_rowsTopToBottom(tester, [_dmId, _groupId]), [_dmId, _groupId]);
      expect(session.messageRow('500000000000000032'), findsOneWidget);
    },
    ready: _readyWithGroup(),
    routes: (transport) => transport.on(
      'GET',
      '/api/v9/channels/$_dmId/messages',
      (_) => jsonResponse(const <Object?>[]),
    ),
  );

  testSession(
    'a group DM moves to the top with a new message',
    (tester, session) async {
      expect(_rowsTopToBottom(tester, [_dmId, _groupId]), [_dmId, _groupId]);

      await session.dispatch('MESSAGE_CREATE', {
        'id': '600000000000000031',
        'channel_id': _groupId,
        'channel_type': 3,
        'author': _friend,
        'content': 'who is in?',
        'timestamp': '2026-11-04T10:00:00.000000+00:00',
      });

      expect(_rowsTopToBottom(tester, [_dmId, _groupId]), [_groupId, _dmId]);
    },
    ready: _readyWithGroup(dmLastMessageId: '500000000000000031'),
  );

  testSession(
    'at login the newest message wins over an older read cursor',
    (tester, session) async {
      expect(_rowsTopToBottom(tester, [_dmId, _groupId]), [_dmId, _groupId]);
    },
    ready: _readyWithGroup(
      dmLastMessageId: '500000000000000031',
      dmAckedId: '310000000000000031',
    ),
  );

  testSession(
    'a new conversation lands where its channel id puts it',
    (tester, session) async {
      await session.dispatch('CHANNEL_CREATE', {
        'id': _newDmId,
        'type': 1,
        'recipients': [_friend],
      });

      expect(_rowsTopToBottom(tester, [_dmId, _groupId, _newDmId]), [
        _groupId,
        _newDmId,
        _dmId,
      ]);
    },
    ready: _readyWithGroup(),
  );
}
