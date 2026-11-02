import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/domain/discord_permissions.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _generalMessage = '900000000000000001';
const _randomMessage = '900000000000000002';

const _guildRail = ValueKey('space-${SessionHarness.guildId}');
const _dmRail = ValueKey('space-direct-messages');

Map<String, Object?> _messageIn(String id, String channelId) => rawMessage(
  id: id,
  channelId: channelId,
  guildId: SessionHarness.guildId,
  authorId: SessionHarness.friendId,
  content: 'Message $id',
);

/// Gives each guild channel one message, so a row on screen names the channel
/// that is open.
void _routeChannels(FakeDiscordTransport transport) {
  transport.on(
    'GET',
    '/api/v9/channels/${SessionHarness.channelId}/messages',
    (_) => jsonResponse([_messageIn(_generalMessage, SessionHarness.channelId)]),
  );
  transport.on(
    'GET',
    '/api/v9/channels/${SessionHarness.otherChannelId}/messages',
    (_) => jsonResponse([
      _messageIn(_randomMessage, SessionHarness.otherChannelId),
    ]),
  );
}

const _categoryId = '300000000000000009';

Finder get _randomRow =>
    find.byKey(const ValueKey('channel-${SessionHarness.otherChannelId}'));

/// The default READY with the guild's second channel inside a category.
Map<String, Object?> _readyWithCategory() => SessionHarness.defaultReady()
  ..['guilds'] = [
    rawGuild(
      id: SessionHarness.guildId,
      name: 'The Forge',
      channels: [
        rawChannel(id: SessionHarness.channelId, name: 'general'),
        {...rawChannel(id: _categoryId, name: 'rooms'), 'type': 4},
        {
          ...rawChannel(id: SessionHarness.otherChannelId, name: 'random'),
          'parent_id': _categoryId,
        },
      ],
      everyonePermissions: '${DiscordPermissions.viewChannel}',
    ),
  ];

/// The default READY without the guild's second channel.
Map<String, Object?> _readyWithoutRandom() => SessionHarness.defaultReady()
  ..['guilds'] = [
    rawGuild(
      id: SessionHarness.guildId,
      name: 'The Forge',
      channels: [rawChannel(id: SessionHarness.channelId, name: 'general')],
      everyonePermissions: '${DiscordPermissions.viewChannel}',
    ),
  ];

/// The default READY with the guild out of reach, as in an outage.
Map<String, Object?> _readyWithGuildUnavailable() =>
    SessionHarness.defaultReady()
      ..['guilds'] = [
        {'id': SessionHarness.guildId, 'unavailable': true},
      ];

List<String> _channelsFetched(SessionHarness session) => [
  for (final request in session.transport.requests)
    if (request.method == 'GET' && request.uri.path.endsWith('/messages'))
      request.uri.pathSegments[3],
];

void main() {
  group('the last channel of a server', () {
    testSession('opens when the server is clicked', (tester, session) async {
      await session.openChannel(SessionHarness.otherChannelId);

      await tester.tap(find.byKey(_dmRail));
      await session.settle();
      await tester.tap(find.byKey(_guildRail));
      await session.settle();

      expect(session.messageRow(_randomMessage), findsOneWidget);
      expect(session.messageRow(_generalMessage), findsNothing);
    }, routes: _routeChannels);
  });

  group('a restart', () {
    testSession('opens the last location', (tester, session) async {
      await session.openChannel(SessionHarness.otherChannelId);

      session.transport.requests.clear();
      await session.relaunch(ready: SessionHarness.defaultReady());

      expect(session.messageRow(_randomMessage), findsOneWidget);
      expect(_channelsFetched(session), [SessionHarness.otherChannelId]);
    }, routes: _routeChannels, onDisk: true);

    testSession('keeps collapsed categories collapsed', (
      tester,
      session,
    ) async {
      await tester.tap(find.byKey(_guildRail));
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('category-$_categoryId')));
      await session.settle();
      expect(_randomRow, findsNothing);

      await session.relaunch(ready: _readyWithCategory());
      await tester.tap(find.byKey(_guildRail));
      await session.settle();

      expect(_randomRow, findsNothing);
      expect(
        find.byKey(const ValueKey('channel-${SessionHarness.channelId}')),
        findsOneWidget,
      );
    }, ready: _readyWithCategory(), onDisk: true);

    testSession(
      'keeps a category collapsed through a launch that lacks its guild',
      (tester, session) async {
        await tester.tap(find.byKey(_guildRail));
        await session.settle();
        await tester.tap(find.byKey(const ValueKey('category-$_categoryId')));
        await session.settle();

        await session.relaunch(ready: _readyWithGuildUnavailable());
        await session.relaunch(ready: _readyWithCategory());
        await tester.tap(find.byKey(_guildRail));
        await session.settle();

        expect(_randomRow, findsNothing);
      },
      ready: _readyWithCategory(),
      onDisk: true,
    );

    testSession(
      'falls back to the first channel when the last one is gone',
      (tester, session) async {
        await session.openChannel(SessionHarness.otherChannelId);

        await session.relaunch(ready: _readyWithoutRandom());

        expect(session.messageRow(_generalMessage), findsOneWidget);
      },
      routes: _routeChannels,
      onDisk: true,
    );

    testSession(
      'goes back to the last location after a launch that lacks its guild',
      (tester, session) async {
        await session.openChannel(SessionHarness.otherChannelId);

        await session.relaunch(ready: _readyWithGuildUnavailable());
        expect(session.messageRow(_randomMessage), findsNothing);
        await session.relaunch(ready: SessionHarness.defaultReady());

        expect(session.messageRow(_randomMessage), findsOneWidget);
      },
      routes: _routeChannels,
      onDisk: true,
    );

    testSession('a link at launch wins over the last location', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.otherChannelId);

      session.transport.requests.clear();
      await session.relaunchWithLink(
        const ChannelLink(
          spaceId: SessionHarness.guildId,
          channelId: SessionHarness.channelId,
        ),
        ready: SessionHarness.defaultReady(),
      );

      expect(session.messageRow(_generalMessage), findsOneWidget);
      expect(_channelsFetched(session), [SessionHarness.channelId]);
    }, routes: _routeChannels, onDisk: true);

    testSession('another account does not get the location', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.otherChannelId);

      await session.relaunch(
        accountId: SessionHarness.friendId,
        ready: SessionHarness.defaultReady(),
      );

      expect(session.messageRow(_randomMessage), findsNothing);
    }, routes: _routeChannels, onDisk: true);

    testSession('after a sign-out the location is gone', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.otherChannelId);

      await session.signOut();
      await session.relaunch(ready: SessionHarness.defaultReady());

      expect(session.messageRow(_randomMessage), findsNothing);
    }, routes: _routeChannels, onDisk: true);
  });
}
