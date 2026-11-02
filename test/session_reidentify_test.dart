import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _guildId = SessionHarness.guildId;
const _channelId = SessionHarness.channelId;
const _dmChannelId = SessionHarness.dmChannelId;
const _newChannelId = '300000000000000099';

String _historyPath(String channelId) => '/api/v9/channels/$channelId/messages';

/// A message sent [minute] minutes into the test's hour, so its place in the
/// timeline is plain to read.
Map<String, Object?> _message(
  String id,
  String channelId,
  int minute, {
  String? guildId,
}) => rawMessage(
  id: id,
  channelId: channelId,
  guildId: guildId,
  authorId: SessionHarness.friendId,
  content: 'message $id',
  timestamp: '2026-07-25T10:${minute.toString().padLeft(2, '0')}:00+00:00',
);

Map<String, Object?> _dm(String id, int minute) =>
    _message(id, _dmChannelId, minute);

/// The default READY with no private channels, as an account with lazy DMs
/// gets it.
Map<String, Object?> _readyWithLazyDms() =>
    SessionHarness.defaultReady()..['private_channels'] = <Object?>[];

const _lazyDms = {
  'lazy_private_channels': [
    {
      'id': _dmChannelId,
      'type': 1,
      'recipient_ids': [SessionHarness.friendId],
    },
  ],
};

Finder _channelRow(String id) => find.byKey(ValueKey('channel-$id'));

Finder _spaceRow(String id) => find.byKey(ValueKey('space-$id'));

/// The session ends and the client identifies afresh, on the same socket, up to
/// the point where Discord is about to send READY.
Future<void> _loseSession(SessionHarness session) async {
  session.socket.receive(const {'op': 9, 'd': false});
  await session.settle();
}

void main() {
  group('private channels', () {
    testSession(
      'a READY with lazy DMs followed by READY_SUPPLEMENTAL keeps the DM and '
      'its messages',
      (tester, session) async {
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        await _loseSession(session);
        await session.dispatch('READY', _readyWithLazyDms());

        // READY alone does not name the DM. It stays until the list is whole.
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        await session.dispatch('READY_SUPPLEMENTAL', _lazyDms);

        expect(session.messageRow('900000000000000001'), findsOneWidget);
      },
      routes: (transport) => transport.on(
        'GET',
        _historyPath(_dmChannelId),
        (_) => jsonResponse([_dm('900000000000000001', 1)]),
      ),
    );

    testSession(
      'a DM that neither dispatch names goes only after READY_SUPPLEMENTAL',
      (tester, session) async {
        expect(_channelRow(_dmChannelId), findsOneWidget);

        await _loseSession(session);
        await session.dispatch('READY', _readyWithLazyDms());
        expect(_channelRow(_dmChannelId), findsOneWidget);

        await session.dispatch('READY_SUPPLEMENTAL', const {
          'lazy_private_channels': <Object?>[],
        });
        expect(_channelRow(_dmChannelId), findsNothing);
      },
    );
  });

  group('guilds', () {
    testSession(
      'a guild marked unavailable keeps its channels and stays on the rail, '
      'and comes back with them',
      (tester, session) async {
        await session.openChannel(_channelId);
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        await _loseSession(session);
        await session.dispatch(
          'READY',
          SessionHarness.defaultReady()
            ..['guilds'] = [
              {'id': _guildId, 'unavailable': true},
            ],
        );

        expect(_spaceRow(_guildId), findsOneWidget);
        expect(_channelRow(_channelId), findsOneWidget);
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        await session.dispatch(
          'GUILD_CREATE',
          (SessionHarness.defaultReady()['guilds']! as List).single
              as Map<String, Object?>,
        );

        expect(_spaceRow(_guildId), findsOneWidget);
        expect(session.messageRow('900000000000000001'), findsOneWidget);
      },
      routes: (transport) => transport.on(
        'GET',
        _historyPath(_channelId),
        (_) => jsonResponse([
          _message('900000000000000001', _channelId, 1, guildId: _guildId),
        ]),
      ),
    );

    testSession('a guild one READY drops is back when a later READY names it', (
      tester,
      session,
    ) async {
      await session.openChannel(_channelId);

      await _loseSession(session);
      await session.dispatch(
        'READY',
        SessionHarness.defaultReady()..['guilds'] = <Object?>[],
      );
      expect(_spaceRow(_guildId), findsNothing);

      await _loseSession(session);
      await session.dispatch('READY', SessionHarness.defaultReady());

      expect(_spaceRow(_guildId), findsOneWidget);
      await session.openChannel(_channelId);
      expect(_channelRow(_channelId), findsOneWidget);
    });

    testSession(
      'a message right behind READY lands after the channel READY brought',
      (tester, session) async {
        await session.openChannel(_channelId);
        await _loseSession(session);
        final ready = SessionHarness.defaultReady();
        (((ready['guilds']! as List).single as Map)['channels'] as List).add(
          rawChannel(id: _newChannelId, name: 'brand-new'),
        );

        await session.dispatch('READY', ready, settle: false);
        await session.dispatch(
          'MESSAGE_CREATE',
          _message('900000000000000009', _newChannelId, 9, guildId: _guildId),
        );

        final name = tester.widget<Text>(find.text('brand-new'));
        expect(name.style?.fontWeight, FontWeight.w600);
      },
    );
  });
}
