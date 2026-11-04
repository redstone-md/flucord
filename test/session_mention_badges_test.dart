import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_snowflake.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _channelId = SessionHarness.channelId;
const _otherChannelId = SessionHarness.otherChannelId;
const _guildId = SessionHarness.guildId;
const _dmChannelId = SessionHarness.dmChannelId;
const _accountId = SessionHarness.currentUserId;

/// An id for a moment [age] ago. Read cursors must be recent, because the app
/// deletes a read state older than 30 days at launch.
String _snowflakeAged(Duration age) => DiscordSnowflake.fromTimestampMillis(
  DateTime.now().subtract(age).millisecondsSinceEpoch,
);

final _cursor = _snowflakeAged(const Duration(hours: 3));
final _firstMessage = _snowflakeAged(const Duration(hours: 2));
final _secondMessage = _snowflakeAged(const Duration(hours: 1));
const _heldRole = '400000000000000001';
const _otherRole = '400000000000000002';

/// READY with a read state on both channels, and the account holding
/// [_heldRole]. The member row is in the compressed shape a real READY sends.
Map<String, Object?> _ready({Map<String, Object?>? guildSettings}) =>
    SessionHarness.defaultReady()
      ..['read_state'] = {
        'version': 1,
        'partial': false,
        'entries': [
          {'id': _channelId, 'last_message_id': _cursor},
          {'id': _otherChannelId, 'last_message_id': _cursor},
        ],
      }
      ..['merged_members'] = [
        [
          {
            'user_id': _accountId,
            'roles': [_heldRole],
          },
        ],
      ]
      ..['user_guild_settings'] = {
        'version': 1,
        'partial': false,
        'entries': [?guildSettings],
      };

Map<String, Object?> _fromFriend(
  String id, {
  String channelId = _channelId,
  List<String> mentionedUsers = const [],
  List<String> mentionedRoles = const [],
}) => {
  ...rawMessage(
    id: id,
    channelId: channelId,
    guildId: _guildId,
    authorId: SessionHarness.friendId,
    content: 'hey',
  ),
  'mentions': [
    for (final user in mentionedUsers) {'id': user, 'username': 'somebody'},
  ],
  'mention_roles': mentionedRoles,
};

Map<String, Object?> _fromAccount(String id) => rawMessage(
  id: id,
  channelId: _channelId,
  guildId: _guildId,
  authorId: _accountId,
  content: 'mine',
);

/// A message in the one-to-one DM with the friend, as the gateway sends it.
Map<String, Object?> _inDirectMessage(
  String id, {
  String authorId = SessionHarness.friendId,
}) => {
  ...rawMessage(
    id: id,
    channelId: _dmChannelId,
    authorId: authorId,
    content: 'hey',
  ),
  'channel_type': 1,
};

Map<String, Object?> _toEveryone(String id) => {
  ..._fromFriend(id),
  'content': '@everyone hey',
  'mention_everyone': true,
};

/// A dispatch that tells the read state something unrelated, so every channel
/// is projected again from what the store holds.
Future<void> _anyOtherEvent(SessionHarness session) =>
    session.dispatch('USER_GUILD_SETTINGS_UPDATE', {
      'guild_id': _guildId,
      'version': 2,
    });

Finder _mentionBadge(String channelId) =>
    find.byKey(ValueKey('channel-mention-$channelId'));

Finder _badgeShowing(String channelId, String count) => find.descendant(
  of: _mentionBadge(channelId),
  matching: find.text(count),
);

/// The count on the rail's DM button. Opening the DM list opens a DM, which
/// reads it, so these tests look at the rail.
final _directMessagesBadge = find.byKey(
  const ValueKey('space-mention-${CommunitySpace.directMessagesId}'),
);

Finder _directMessagesBadgeShowing(String count) =>
    find.descendant(of: _directMessagesBadge, matching: find.text(count));

/// Moves to another channel of the open server by its row, as a user does.
///
/// `session.openChannel` also taps the server, and that opens the server's last
/// channel again, which acks it and hides what these tests look for.
Future<void> _switchChannel(
  WidgetTester tester,
  SessionHarness session,
  String channelId,
) async {
  await tester.tap(find.byKey(ValueKey('channel-$channelId')));
  await session.settle();
}

/// Whether the row of a channel that is not selected reads as unread. The
/// sidebar shows this by the weight of the channel's name.
bool _rowLooksUnread(WidgetTester tester, String channelId, String name) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byKey(ValueKey('channel-$channelId')),
      matching: find.text(name),
    ),
  );
  return text.style!.fontWeight == FontWeight.w500;
}

Iterable<Uri> _acksOf(SessionHarness session, String channelId) => session
    .transport
    .requests
    .where(
      (request) =>
          request.method == 'POST' &&
          request.uri.path.startsWith('/api/v9/channels/$channelId/messages') &&
          request.uri.path.endsWith('/ack'),
    )
    .map((request) => request.uri);

void main() {
  group('a mention of the account', () {
    testSession(
      'raises the badge of the channel it lands in, once per message',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedUsers: [_accountId]),
        );
        expect(_badgeShowing(_channelId, '1'), findsOneWidget);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_secondMessage, mentionedUsers: [_accountId]),
        );
        expect(_badgeShowing(_channelId, '2'), findsOneWidget);
      },
      ready: _ready(),
    );

    testSession(
      'of somebody else raises nothing',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedUsers: [SessionHarness.friendId]),
        );

        expect(_mentionBadge(_channelId), findsNothing);
      },
      ready: _ready(),
    );

    testSession(
      'in the channel on screen leaves no badge, and acks at once',
      (tester, session) async {
        session.transport.on(
          'POST',
          '/api/v9/channels/$_channelId/messages/$_firstMessage/ack',
          (_) => jsonResponse({'token': null}),
        );
        await session.openChannel(_channelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedUsers: [_accountId]),
        );

        expect(_mentionBadge(_channelId), findsNothing);
        expect(_acksOf(session, _channelId), hasLength(1));
      },
      ready: _ready(),
    );

    testSession(
      'that a server ack already passed raises nothing',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch('MESSAGE_ACK', {
          'channel_id': _channelId,
          'message_id': _secondMessage,
          'version': 2,
        });
        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedUsers: [_accountId]),
        );

        expect(_mentionBadge(_channelId), findsNothing);
      },
      ready: _ready(),
    );
  });

  group('a one-to-one DM', () {
    testSession(
      'raises the badge by one for each message from the other person',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _inDirectMessage(_firstMessage),
        );
        expect(_directMessagesBadgeShowing('1'), findsOneWidget);

        await session.dispatch(
          'MESSAGE_CREATE',
          _inDirectMessage(_secondMessage),
        );
        expect(_directMessagesBadgeShowing('2'), findsOneWidget);
      },
      ready: _ready(),
    );

    testSession(
      'raises nothing for a message of the account',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _inDirectMessage(_firstMessage, authorId: _accountId),
        );

        expect(_directMessagesBadge, findsNothing);
      },
      ready: _ready(),
    );
  });

  group('@everyone or @here', () {
    testSession(
      'raises the badge of the channel by one',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch('MESSAGE_CREATE', _toEveryone(_firstMessage));

        expect(_badgeShowing(_channelId, '1'), findsOneWidget);
      },
      ready: _ready(),
    );

    testSession(
      'raises nothing in a guild that suppresses it',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch('MESSAGE_CREATE', _toEveryone(_firstMessage));

        expect(_mentionBadge(_channelId), findsNothing);
      },
      ready: _ready(
        guildSettings: {'guild_id': _guildId, 'suppress_everyone': true},
      ),
    );

    testSession(
      'from the account raises nothing',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch('MESSAGE_CREATE', {
          ..._toEveryone(_firstMessage),
          'author': {'id': _accountId, 'username': 'me'},
        });

        expect(_mentionBadge(_channelId), findsNothing);
      },
      ready: _ready(),
    );
  });

  group('a mention of a role', () {
    testSession(
      'the account holds counts like a mention of the account',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedRoles: [_heldRole]),
        );

        expect(_badgeShowing(_channelId, '1'), findsOneWidget);
      },
      ready: _ready(),
    );

    testSession(
      'the account does not hold raises nothing',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedRoles: [_otherRole]),
        );

        expect(_mentionBadge(_channelId), findsNothing);
      },
      ready: _ready(),
    );

    testSession(
      'the account gained after READY counts',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch('GUILD_MEMBER_UPDATE', {
          'guild_id': _guildId,
          'user': {'id': _accountId, 'username': 'me'},
          'roles': [_heldRole, _otherRole],
        });
        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedRoles: [_otherRole]),
        );

        expect(_badgeShowing(_channelId, '1'), findsOneWidget);
      },
      ready: _ready(),
    );

    testSession(
      'raises nothing in a guild that suppresses role mentions',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedRoles: [_heldRole]),
        );

        expect(_mentionBadge(_channelId), findsNothing);
      },
      ready: _ready(
        guildSettings: {'guild_id': _guildId, 'suppress_roles': true},
      ),
    );

    testSession(
      'is listed with the mentions in the inbox',
      (tester, session) async {
        await session.openChannel(_otherChannelId);
        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedRoles: [_heldRole]),
        );

        await tester.tap(find.byKey(const ValueKey('open-inbox')));
        await session.settle();
        await tester.tap(find.textContaining('Mentions').last);
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('inbox-mention-$_firstMessage')),
          findsOneWidget,
        );
      },
      ready: _ready(),
    );
  });

  group('a channel set to only mentions', () {
    Map<String, Object?> onlyMentionsReady() => _ready(
      guildSettings: {
        'guild_id': _guildId,
        'channel_overrides': [
          {
            'channel_id': _channelId,
            'flags': ChannelOverrideFlags.unreadsOnlyMentions,
          },
        ],
      },
    )..['notification_settings'] = {
      'flags': AccountNotificationFlags.useNewNotifications,
    };

    testSession(
      'stays quiet for a plain message',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch('MESSAGE_CREATE', _fromFriend(_firstMessage));

        expect(_rowLooksUnread(tester, _channelId, 'general'), isFalse);
      },
      ready: onlyMentionsReady(),
    );

    testSession(
      'shows its pip for a mention of the account',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedUsers: [_accountId]),
        );

        expect(_rowLooksUnread(tester, _channelId, 'general'), isTrue);
      },
      ready: onlyMentionsReady(),
    );

    testSession(
      'shows its pip for a mention of one of its roles',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedRoles: [_heldRole]),
        );

        expect(_rowLooksUnread(tester, _channelId, 'general'), isTrue);
      },
      ready: onlyMentionsReady(),
    );

    testSession(
      'lights the server rail for a mention while another server is open',
      (tester, session) async {
        final pip = find.byKey(const ValueKey('space-indicator-$_guildId'));

        await session.dispatch('MESSAGE_CREATE', _fromFriend(_firstMessage));
        expect(pip, findsNothing);

        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_secondMessage, mentionedUsers: [_accountId]),
        );
        expect(pip, findsOneWidget);
      },
      ready: onlyMentionsReady(),
    );
  });

  group("the account's own message", () {
    testSession(
      'from the gateway leaves the channel read after a switch and another '
      'event, with no ack on the wire',
      (tester, session) async {
        await session.openChannel(_channelId);

        await session.dispatch('MESSAGE_CREATE', _fromAccount(_firstMessage));
        await _switchChannel(tester, session, _otherChannelId);
        await _anyOtherEvent(session);

        expect(_rowLooksUnread(tester, _channelId, 'general'), isFalse);
        expect(
          _acksOf(session, _channelId).where(
            (uri) => uri.path.contains(_firstMessage),
          ),
          isEmpty,
        );
      },
      ready: _ready(),
    );

    testSession(
      'sent from the composer leaves the channel read before the gateway '
      'echoes it',
      (tester, session) async {
        session.transport.on(
          'POST',
          '/api/v9/channels/$_channelId/messages',
          (_) => jsonResponse(_fromAccount(_firstMessage)),
        );
        await session.openChannel(_channelId);

        await tester.enterText(
          find.byKey(const ValueKey('message-composer')),
          'mine',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await session.settle();
        await _switchChannel(tester, session, _otherChannelId);
        await _anyOtherEvent(session);

        expect(_rowLooksUnread(tester, _channelId, 'general'), isFalse);
      },
      ready: _ready(),
    );

    testSession(
      'sent from another device leaves a channel not on screen read',
      (tester, session) async {
        await session.openChannel(_otherChannelId);

        await session.dispatch('MESSAGE_CREATE', _fromAccount(_firstMessage));
        await _anyOtherEvent(session);

        expect(_rowLooksUnread(tester, _channelId, 'general'), isFalse);
      },
      ready: _ready(),
    );

    testSession(
      'clears the badge the channel had',
      (tester, session) async {
        await session.openChannel(_otherChannelId);
        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedUsers: [_accountId]),
        );
        expect(_mentionBadge(_channelId), findsOneWidget);

        await session.dispatch('MESSAGE_CREATE', _fromAccount(_secondMessage));

        expect(_mentionBadge(_channelId), findsNothing);
      },
      ready: _ready(),
    );
  });

  group('a server MESSAGE_ACK', () {
    testSession(
      'clears the count',
      (tester, session) async {
        await session.openChannel(_otherChannelId);
        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedUsers: [_accountId]),
        );
        expect(_mentionBadge(_channelId), findsOneWidget);

        await session.dispatch('MESSAGE_ACK', {
          'channel_id': _channelId,
          'message_id': _firstMessage,
          'version': 2,
        });

        expect(_mentionBadge(_channelId), findsNothing);
      },
      ready: _ready(),
    );

    testSession(
      'replaces the local count with its own',
      (tester, session) async {
        await session.openChannel(_otherChannelId);
        await session.dispatch(
          'MESSAGE_CREATE',
          _fromFriend(_firstMessage, mentionedUsers: [_accountId]),
        );

        await session.dispatch('MESSAGE_ACK', {
          'channel_id': _channelId,
          'message_id': _cursor,
          'mention_count': 3,
          'manual': true,
          'version': 2,
        });

        expect(_badgeShowing(_channelId, '3'), findsOneWidget);
      },
      ready: _ready(),
    );
  });
}
