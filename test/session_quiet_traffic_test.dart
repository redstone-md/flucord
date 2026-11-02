import 'package:flucord/src/domain/discord_snowflake.dart';
import 'package:flucord/src/presentation/conversation_pane.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/build_counter.dart';
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
Future<void> _presence(SessionHarness session, String userId) =>
    session.dispatch('PRESENCE_UPDATE', {
      'user': {'id': userId},
      'guild_id': _guildId,
      'status': 'dnd',
      'activities': <Object?>[],
      'client_status': {'desktop': 'dnd'},
    });

/// Builds of the shell. Everything the shell shows hangs from a
/// [ListenableBuilder] on a controller, so a notification always counts here.
///
/// A test does not ask for no builds at all. The composer's text field rebuilds
/// itself when a platform answer arrives, at a time that depends on machine load.
int _shellBuilds(WidgetBuilds builds) => builds.of<ListenableBuilder>();

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

void main() {
  group('presence', () {
    testSession('for somebody the app does not know does not build the shell', (
      tester,
      session,
    ) async {
      await session.openChannel(_channelId);

      final builds = await countBuilds(
        () => _presence(session, '100000000000000099'),
      );

      expect(_shellBuilds(builds), 0);
    });

    testSession('for somebody the app knows still reaches the screen', (
      tester,
      session,
    ) async {
      await session.openChannel(_channelId);

      final builds = await countBuilds(() => _presence(session, _friendId));

      expect(_shellBuilds(builds), greaterThan(0));
    });
  });

  group('read state', () {
    testSession(
      'an ack that repeats the cursor does not build the shell',
      (tester, session) async {
        await session.openChannel(_channelId);

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
      await session.openChannel(_channelId);

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
        await session.openChannel(_channelId);

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
      await session.openChannel(_channelId);
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
      await session.openChannel(_channelId);

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
      await session.openChannel(_channelId);

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
      await session.openChannel(_channelId);
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
      await session.openChannel(_channelId);
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
      await session.openChannel(_channelId);
      await _typing(session, channelId: _otherChannelId);
      expect(find.text('Friend is typing...'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('channel-$_otherChannelId')));
      await session.settle();

      expect(find.text('Friend is typing...'), findsOneWidget);
    });
  });
}
