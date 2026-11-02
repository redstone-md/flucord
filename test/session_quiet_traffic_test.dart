import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_snowflake.dart';
import 'package:flucord/src/presentation/conversation_pane.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/chat_scope.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flucord/src/presentation/widgets/presence_indicator.dart';
import 'package:flucord/src/presentation/widgets/typing_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/build_counter.dart';
import 'support/channel_history_fixture.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _channelId = SessionHarness.channelId;
const _otherChannelId = SessionHarness.otherChannelId;
const _guildId = SessionHarness.guildId;
const _friendId = SessionHarness.friendId;

/// A typing event as the gateway carries it.
Future<void> _typing(
  SessionHarness session, {
  required String channelId,
  bool settle = true,
}) => session.dispatch('TYPING_START', {
  'channel_id': channelId,
  'guild_id': _guildId,
  'user_id': _friendId,
  'timestamp': 1,
}, settle: settle);

/// A presence as the gateway carries it.
Future<void> _presence(
  SessionHarness session,
  String userId, {
  String guildId = _guildId,
  String status = 'dnd',
  bool settle = true,
}) => session.dispatch('PRESENCE_UPDATE', {
  'user': {'id': userId},
  'guild_id': guildId,
  'status': status,
  'activities': <Object?>[],
  'client_status': {'desktop': status},
}, settle: settle);

/// Builds of the shell. Everything the shell shows hangs from a
/// [ListenableBuilder] on a controller, so a notification always counts here.
///
/// A test does not ask for no builds at all, because the composer's text field
/// can rebuild itself at a time that depends on machine load.
int _shellBuilds(WidgetBuilds builds) => builds.of<ListenableBuilder>();

/// Opens the channel, then waits for the app to come to rest, so a test counts
/// only what its own event causes.
///
/// A channel opened earlier in the launch can still be loading its history, and
/// under load it finishes late and notifies. So this waits for real time as well
/// as on the fake clock, until two rounds in a row build nothing in the shell.
Future<void> _openAndRest(
  WidgetTester tester,
  SessionHarness session,
  String channelId,
) async {
  await session.openChannel(channelId);
  await _rest(tester, session);
}

/// Waits for the app to come to rest. See [_openAndRest].
Future<void> _rest(WidgetTester tester, SessionHarness session) async {
  var quietRounds = 0;
  for (var round = 0; round < 40 && quietRounds < 2; round++) {
    final builds = await countBuilds(() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await session.settle();
    });
    quietRounds = _shellBuilds(builds) == 0 ? quietRounds + 1 : 0;
  }
  expect(quietRounds, 2, reason: 'The app never came to rest.');
}

/// An id for a moment [age] ago. Read cursors must be recent, because the app
/// deletes a read state older than 30 days at launch.
String _snowflakeAged(Duration age) => DiscordSnowflake.fromTimestampMillis(
  DateTime.now().subtract(age).millisecondsSinceEpoch,
);

final _cursor = _snowflakeAged(const Duration(hours: 3));
final _newest = _snowflakeAged(const Duration(hours: 1));

const _farGuildId = '200000000000000009';
const _farChannelId = '300000000000000009';

/// READY with a second server, and a read state on a channel of each.
Map<String, Object?> _twoServers() {
  final ready = SessionHarness.defaultReady();
  ready['guilds'] = [
    ...ready['guilds']! as List<Object?>,
    rawGuild(
      id: _farGuildId,
      name: 'Far Away',
      channels: [
        rawChannel(id: _farChannelId, name: 'far', lastMessageId: _cursor),
      ],
    ),
  ];
  ready['read_state'] = {
    'version': 1,
    'partial': false,
    'entries': [
      {'id': _channelId, 'last_message_id': _cursor},
      {'id': _farChannelId, 'last_message_id': _cursor},
    ],
  };
  return ready;
}

/// People the app knows only from the far server.
final _farMembers = [
  for (var index = 0; index < 50; index++) '40000000000000${1000 + index}',
];

Future<void> _meetFarMembers(SessionHarness session) async {
  for (final id in _farMembers) {
    await session.dispatch('GUILD_MEMBER_ADD', {
      'guild_id': _farGuildId,
      'user': {'id': id, 'username': 'far-$id'},
      'roles': <Object?>[],
    }, settle: false);
  }
  await session.settle();
}

const _spokenId = '900000000000000001';
const _madeLaterId = '300000000000000077';

/// Somebody says [body] in the open channel.
Future<void> _say(SessionHarness session, String body) => session.dispatch(
  'MESSAGE_CREATE',
  rawMessage(
    id: _spokenId,
    channelId: _channelId,
    guildId: _guildId,
    authorId: _friendId,
    content: body,
  ),
);

Future<void> _createChannel(SessionHarness session) => session.dispatch(
  'CHANNEL_CREATE',
  {...rawChannel(id: _madeLaterId, name: 'made-later'), 'guild_id': _guildId},
);

/// The status the row of [_spokenId] draws on its author's avatar.
Presence _authorStatus(WidgetTester tester, SessionHarness session) => tester
    .widget<PresenceIndicator>(
      find.descendant(
        of: session.messageRow(_spokenId),
        matching: find.byKey(const ValueKey('member-presence-$_friendId')),
      ),
    )
    .presence
    .status;

/// Lets the real event loop deliver what the socket received, then moves the
/// fake clock by exactly [time]. [SessionHarness.settle] would move it too far.
Future<void> _passWithoutSettling(WidgetTester tester, Duration time) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(time);
}

/// Fills the open channel with more rows than fit on the screen.
void _routeHistory(FakeDiscordTransport transport) => transport.on(
  'GET',
  ChannelHistoryFixture.messagesPath,
  (_) => jsonResponse(ChannelHistoryFixture.page(0, 100)),
);

void main() {
  group('the timeline', () {
    testSession(
      'builds no row for 50 presences from another server',
      (tester, session) async {
        await _openAndRest(tester, session, _channelId);
        await _meetFarMembers(session);
        expect(find.byType(MessageItem), findsWidgets);

        final builds = await countBuilds(() async {
          for (final id in _farMembers) {
            await _presence(session, id, guildId: _farGuildId, settle: false);
          }
          await session.settle();
        });
        expect(_shellBuilds(builds), greaterThan(0));
        expect(builds.of<MessageItem>(), 0);

        // The control: an edit to a row that is not mounted changes no row on
        // screen, and the counter still sees the list build them again.
        final control = await countBuilds(
          () => session.dispatch(
            'MESSAGE_UPDATE',
            ChannelHistoryFixture.message(0, content: 'edited'),
          ),
        );
        expect(session.messageRow(ChannelHistoryFixture.idOf(0)), findsNothing);
        expect(control.of<MessageItem>(), greaterThan(0));
      },
      ready: _twoServers(),
      routes: _routeHistory,
    );

    testSession(
      'builds no row for a message in another server',
      (tester, session) async {
        await _openAndRest(tester, session, _channelId);
        expect(find.byType(MessageItem), findsWidgets);

        final builds = await countBuilds(
          () => session.dispatch(
            'MESSAGE_CREATE',
            rawMessage(
              id: _newest,
              channelId: _farChannelId,
              guildId: _farGuildId,
              authorId: _farMembers.first,
              content: 'far away',
            ),
          ),
        );

        expect(_shellBuilds(builds), greaterThan(0));
        expect(builds.of<MessageItem>(), 0);
      },
      ready: _twoServers(),
      routes: _routeHistory,
    );

    testSession('a rename of somebody mentioned redraws the mention', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      await _meetFarMembers(session);
      final mentioned = _farMembers.first;
      await _say(session, 'hello <@$mentioned>');

      await session.dispatch('GUILD_MEMBER_UPDATE', {
        'guild_id': _farGuildId,
        'user': {'id': mentioned, 'username': 'far'},
        'nick': 'Renamed',
        'roles': <Object?>[],
      });

      expect(find.text('@Renamed'), findsOneWidget);
    }, ready: _twoServers());

    testSession('a rename of a mentioned channel redraws the mention', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      await _say(session, 'see <#$_farChannelId>');

      await session.dispatch('CHANNEL_UPDATE', {
        ...rawChannel(id: _farChannelId, name: 'renamed'),
        'guild_id': _farGuildId,
      });

      expect(find.text('#renamed'), findsOneWidget);
    }, ready: _twoServers());

    testSession(
      'Forward offers a channel made after the row was drawn',
      (tester, session) async {
        await _openAndRest(tester, session, _channelId);
        await _say(session, 'pass this on');

        await _createChannel(session);
        await tester.tap(
          session.messageRow(_spokenId),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await session.settle();
        await tester.tap(find.byKey(const ValueKey('message-menu-forward')));
        await session.settle();

        expect(
          find.byKey(const ValueKey('message-forward-$_madeLaterId')),
          findsOneWidget,
        );
      },
      ready: _twoServers(),
      platform: TargetPlatform.windows,
    );

    testSession('a link opens a channel made after the row was drawn', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      final link =
          'https://discord.com/channels/$_guildId/$_madeLaterId/$_cursor';
      await _say(session, link);
      final chat = ChatScope.read(
        tester.element(session.messageRow(_spokenId)),
      );

      await _createChannel(session);
      // The text widget is as wide as the row, so its centre misses the link.
      await tester.tapAt(
        tester.getTopLeft(find.text(link, findRichText: true)) +
            const Offset(20, 8),
      );
      await session.settle();

      expect(chat.activeChannelId, _madeLaterId);
    }, ready: _twoServers());
  });

  group('presence', () {
    testSession('for somebody the app does not know does not build the shell', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);

      final builds = await countBuilds(
        () => _presence(session, '100000000000000099'),
      );

      expect(_shellBuilds(builds), 0);
    });

    testSession('for somebody the app knows still reaches the screen', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);

      final builds = await countBuilds(() => _presence(session, _friendId));

      expect(_shellBuilds(builds), greaterThan(0));
    });

    testSession('in a burst folds once, and the last one for a person wins', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      await _say(session, 'on screen');
      await _meetFarMembers(session);
      await _rest(tester, session);
      final chat = ChatScope.read(
        tester.element(session.messageRow(_spokenId)),
      );
      var folds = 0;
      void countFold() => folds++;
      chat.addListener(countFold);
      addTearDown(() => chat.removeListener(countFold));

      for (final id in _farMembers) {
        await _presence(session, id, guildId: _farGuildId, settle: false);
        await _passWithoutSettling(tester, const Duration(milliseconds: 1));
      }
      await _presence(session, _friendId, settle: false);
      await _passWithoutSettling(tester, const Duration(milliseconds: 1));
      await _presence(session, _friendId, status: 'idle', settle: false);
      await session.settle();

      expect(folds, 1);
      expect(_authorStatus(tester, session), Presence.idle);
    });

    testSession('waits for the window, then updates the author on screen', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      await _say(session, 'on screen');
      await _rest(tester, session);
      final before = _authorStatus(tester, session);
      expect(before, isNot(Presence.doNotDisturb));

      await _presence(session, _friendId, settle: false);
      await _passWithoutSettling(tester, const Duration(milliseconds: 99));
      expect(_authorStatus(tester, session), before);

      await _passWithoutSettling(tester, const Duration(milliseconds: 151));
      expect(_authorStatus(tester, session), Presence.doNotDisturb);
    });

    testSession('that repeats what the app shows builds nothing', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      await _say(session, 'on screen');
      await _presence(session, _friendId);
      await _rest(tester, session);

      final builds = await countBuilds(() => _presence(session, _friendId));

      expect(_shellBuilds(builds), 0);
      expect(builds.of<MessageItem>(), 0);
    });
  });

  group('traffic that changes nothing', () {
    testSession('a member update builds nothing', (tester, session) async {
      await _openAndRest(tester, session, _channelId);
      Future<void> update() => session.dispatch('GUILD_MEMBER_UPDATE', {
        'guild_id': _guildId,
        'user': {'id': _friendId, 'username': 'friend'},
        'nick': 'Friend',
        'roles': <Object?>[],
      });
      await update();
      await _rest(tester, session);

      final builds = await countBuilds(update);

      expect(_shellBuilds(builds), 0);
    });

    testSession('a delete of a message the app does not hold builds nothing', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);

      final builds = await countBuilds(
        () => session.dispatch('MESSAGE_DELETE', {
          'id': '900000000000000099',
          'channel_id': _channelId,
          'guild_id': _guildId,
        }),
      );

      expect(_shellBuilds(builds), 0);
    });
  });

  group('read state', () {
    testSession(
      'an ack that repeats the cursor does not build the shell',
      (tester, session) async {
        await _openAndRest(tester, session, _channelId);

        final builds = await countBuilds(
          () => session.dispatch('MESSAGE_ACK', {
            'channel_id': _channelId,
            'message_id': _cursor,
            'version': 2,
          }),
        );

        expect(_shellBuilds(builds), 0);
      },
      ready: _twoServers(),
    );

    testSession('a message in another server keeps the channel list', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);

      final builds = await countBuilds(
        () => session.dispatch(
          'MESSAGE_CREATE',
          rawMessage(
            id: _newest,
            channelId: _farChannelId,
            guildId: _farGuildId,
            authorId: _friendId,
            content: 'far away',
          ),
        ),
      );

      expect(builds.of<ChannelSidebar>(), 0);
    }, ready: _twoServers());

    testSession(
      'a cursor moving in another server keeps the channel list',
      (tester, session) async {
        await _openAndRest(tester, session, _channelId);

        final builds = await countBuilds(
          () => session.dispatch('MESSAGE_ACK', {
            'channel_id': _farChannelId,
            'message_id': _newest,
            'mention_count': 2,
            'manual': true,
            'version': 2,
          }),
        );

        expect(builds.of<ListenableBuilder>(), greaterThan(0));
        expect(builds.of<ChannelSidebar>(), 0);
      },
      ready: _twoServers(),
    );

    testSession('muting the open server still marks the channel list', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      expect(find.byKey(const ValueKey('space-muted')), findsNothing);

      await session.dispatch('USER_GUILD_SETTINGS_UPDATE', {
        'guild_id': _guildId,
        'muted': true,
        'version': 2,
      });

      expect(find.byKey(const ValueKey('space-muted')), findsOneWidget);
    }, ready: _twoServers());
  });

  group('typing', () {
    testSession('in other channels does not build the shell', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);

      final builds = await countBuilds(() async {
        for (var i = 0; i < 1000; i++) {
          await _typing(session, channelId: _otherChannelId, settle: false);
        }
        await session.settle();
        // The indicators of the other channel run out here.
        await tester.pump(const Duration(seconds: 10));
        await session.settle();
      });

      expect(_shellBuilds(builds), 0);
    });

    testSession('in the active channel shows, without building the shell', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);

      final builds = await countBuilds(
        () => _typing(session, channelId: _channelId),
      );

      expect(find.text('Friend is typing...'), findsOneWidget);
      expect(builds.of<TypingIndicator>(), greaterThan(0));
      // The indicator's own builder, and none of the shell's.
      expect(_shellBuilds(builds), 1);
      expect(builds.of<ConversationPane>(), 0);
      expect(builds.of<ChannelSidebar>(), 0);
    });

    testSession('from somebody already typing builds nothing', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      await _typing(session, channelId: _channelId);

      final builds = await countBuilds(
        () => _typing(session, channelId: _channelId),
      );

      expect(builds.of<TypingIndicator>(), 0);
    });

    testSession('runs out in the active channel after nine seconds', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      await _typing(session, channelId: _channelId);

      await tester.pump(const Duration(seconds: 8));
      expect(find.text('Friend is typing...'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await session.settle();
      expect(find.text('Friend is typing...'), findsNothing);
    });

    testSession('in another channel shows once that channel opens', (
      tester,
      session,
    ) async {
      await _openAndRest(tester, session, _channelId);
      await _typing(session, channelId: _otherChannelId);
      expect(find.text('Friend is typing...'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('channel-$_otherChannelId')));
      await session.settle();

      expect(find.text('Friend is typing...'), findsOneWidget);
    });
  });
}
