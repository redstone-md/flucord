import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/domain/discord_snowflake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _channelId = SessionHarness.channelId;
const _otherChannelId = SessionHarness.otherChannelId;
const _dmChannelId = SessionHarness.dmChannelId;
const _guildId = SessionHarness.guildId;

/// How long a plain ack waits before it goes out.
const _ackDebounce = Duration(seconds: 3);

/// An id for a moment [age] ago.
String _snowflakeAged(Duration age) => DiscordSnowflake.fromTimestampMillis(
  DateTime.now().subtract(age).millisecondsSinceEpoch,
);

final _cursor = _snowflakeAged(const Duration(hours: 3));
final _newest = _snowflakeAged(const Duration(hours: 1));

/// Older than the 30 days the app keeps a read state for.
final _staleCursor = _snowflakeAged(const Duration(days: 40));

/// READY with the [cursors] the account holds. Each channel they name is at
/// [_newest]. Any other channel names no message, so opening it acks nothing.
Map<String, Object?> _ready(Map<String, String> cursors) {
  String? newestOf(String id) => cursors.containsKey(id) ? _newest : null;
  final ready = SessionHarness.defaultReady();
  ready['guilds'] = [
    rawGuild(
      id: _guildId,
      name: 'The Forge',
      channels: [
        rawChannel(
          id: _channelId,
          name: 'general',
          lastMessageId: newestOf(_channelId),
        ),
        rawChannel(
          id: _otherChannelId,
          name: 'random',
          lastMessageId: newestOf(_otherChannelId),
        ),
      ],
      everyonePermissions: '1024',
    ),
  ];
  ready['private_channels'] = [
    {
      'id': _dmChannelId,
      'type': 1,
      'recipient_ids': [SessionHarness.friendId],
      'last_message_id': newestOf(_dmChannelId),
    },
  ];
  ready['read_state'] = {
    'version': 1,
    'partial': false,
    'entries': [
      for (final MapEntry(key: id, value: cursor) in cursors.entries)
        {'id': id, 'last_message_id': cursor},
    ],
  };
  return ready;
}

final _readOnMyPhone = rawMessage(
  id: _newest,
  channelId: _otherChannelId,
  guildId: _guildId,
  authorId: SessionHarness.friendId,
  content: 'read on my phone',
);

/// A channel row shows unread by the weight of its name.
bool _rowIsBold(WidgetTester tester, String channelId, String name) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byKey(ValueKey('channel-$channelId')),
      matching: find.text(name),
    ),
  );
  return text.style!.fontWeight == FontWeight.w600;
}

/// Opens the server, which lands on its first channel, and brings the other
/// channel's row into view. That channel names no message, so nothing is acked
/// and no read state update comes from this.
Future<void> _showChannelRows(
  WidgetTester tester,
  SessionHarness session,
) async {
  await tester.tap(find.byKey(const ValueKey('space-$_guildId')));
  await session.settle();
}

Iterable<String> _ackedChannels(SessionHarness session) => session
    .transport
    .requests
    .where(
      (request) =>
          request.method == 'POST' && request.uri.path.endsWith('/ack'),
    )
    .map((request) => request.uri.pathSegments[3]);

void main() {
  group('after launch, read state from READY shows with no further event', () {
    testSession(
      'a channel behind its cursor is unread',
      (tester, session) async {
        await _showChannelRows(tester, session);

        expect(_rowIsBold(tester, _otherChannelId, 'random'), isTrue);
      },
      ready: _ready({_otherChannelId: _cursor}),
    );

    testSession('a channel at its cursor is read', (tester, session) async {
      await _showChannelRows(tester, session);

      expect(_rowIsBold(tester, _otherChannelId, 'random'), isFalse);
    }, ready: _ready({_otherChannelId: _newest}));

    testSession(
      'a cursor the app collects as too old leaves no pip',
      (tester, session) async {
        await _showChannelRows(tester, session);

        expect(_rowIsBold(tester, _otherChannelId, 'random'), isFalse);
      },
      ready: _ready({_otherChannelId: _staleCursor}),
    );
  });

  testSession(
    'a boundary saved in the cache does not survive READY saying it was read',
    (tester, session) async {
      await session.openChannel(_channelId);
      await session.dispatch('MESSAGE_CREATE', _readOnMyPhone);

      await session.relaunch(ready: _ready({_otherChannelId: _newest}));
      await session.openChannel(_otherChannelId);

      expect(session.messageRow(_newest), findsOneWidget);
      expect(
        find.byKey(const ValueKey('unread-message-boundary')),
        findsNothing,
      );
    },
    ready: _ready({_otherChannelId: _cursor}),
    onDisk: true,
    routes: (transport) => transport.on(
      'GET',
      '/api/v9/channels/$_otherChannelId/messages',
      (_) => jsonResponse([_readOnMyPhone]),
    ),
  );

  group('a link opened at launch', () {
    Map<String, Object?> unreadEverywhere() =>
        _ready({_dmChannelId: _cursor, _channelId: _cursor});

    testSession(
      'leaves its channel on screen and acked, not the first channel',
      (tester, session) async {
        await tester.pump(_ackDebounce);
        await session.settle();

        expect(session.messageRow(_newest), findsOneWidget);
        expect(_ackedChannels(session), [_channelId]);
        expect(
          session.transport.requests.where(
            (request) => request.uri.path.contains('/$_dmChannelId/'),
          ),
          isEmpty,
        );
      },
      ready: unreadEverywhere(),
      linkAtLaunch: const ChannelLink(spaceId: _guildId, channelId: _channelId),
      routes: (transport) => transport.on(
        'GET',
        '/api/v9/channels/$_channelId/messages',
        (_) => jsonResponse([
          rawMessage(
            id: _newest,
            channelId: _channelId,
            guildId: _guildId,
            authorId: SessionHarness.friendId,
            content: 'the linked channel',
          ),
        ]),
      ),
    );
  });
}
