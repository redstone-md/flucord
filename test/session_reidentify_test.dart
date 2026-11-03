import 'dart:async';

import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/presentation/widgets/status_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _guildId = SessionHarness.guildId;
const _channelId = SessionHarness.channelId;
const _otherChannelId = SessionHarness.otherChannelId;
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

Map<String, Object?> _guildMessage(String id, int minute) =>
    _message(id, _channelId, minute, guildId: _guildId);

Map<String, Object?> _otherMessage(String id, int minute) =>
    _message(id, _otherChannelId, minute, guildId: _guildId);

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

Map<String, Object?> _guildOf(Map<String, Object?> ready) =>
    (ready['guilds']! as List).single as Map<String, Object?>;

Map<String, Object?> _defaultGuild() => _guildOf(SessionHarness.defaultReady());

Map<String, Object?> _readyWithGuildOut() =>
    SessionHarness.defaultReady()
      ..['guilds'] = [
        {'id': _guildId, 'unavailable': true},
      ];

Map<String, Object?> _readyWithNoGuilds() =>
    SessionHarness.defaultReady()..['guilds'] = <Object?>[];

/// The default READY, with [messageId] as the newest message of [_channelId].
Map<String, Object?> _readyNamingLatest(String messageId) {
  final ready = SessionHarness.defaultReady();
  (_guildOf(ready)['channels']! as List)[0] = rawChannel(
    id: _channelId,
    name: 'general',
    lastMessageId: messageId,
  );
  return ready;
}

Finder _channelRow(String id) => find.byKey(ValueKey('channel-$id'));

Finder _spaceRow(String id) => find.byKey(ValueKey('space-$id'));

/// The session ends and the client identifies afresh, on the same socket, up to
/// the point where Discord is about to send READY.
Future<void> _loseSession(SessionHarness session) async {
  session.socket.receive(const {'op': 9, 'd': false});
  await session.settle();
}

/// A whole re-identify, with a READY that changes nothing.
Future<void> _identifyAgain(SessionHarness session) async {
  await _loseSession(session);
  await session.dispatch('READY', SessionHarness.defaultReady());
}

int _historyRequests(SessionHarness session, String channelId) => session
    .transport
    .requests
    .where(
      (request) =>
          request.method == 'GET' &&
          request.uri.path == _historyPath(channelId),
    )
    .length;

/// What [_channelId] holds from the start of a test: one message.
void _oneMessage(FakeDiscordTransport transport) => transport.on(
  'GET',
  _historyPath(_channelId),
  (_) => jsonResponse([_guildMessage('900000000000000001', 1)]),
);

void _historyFails(SessionHarness session) => session.transport.on(
  'GET',
  _historyPath(_channelId),
  (_) => jsonResponse({'message': 'Down'}, statusCode: 400),
);

/// Discord answers newest first.
void _historyAnswers(
  SessionHarness session,
  String channelId,
  List<Map<String, Object?>> newestFirst,
) => session.transport.on(
  'GET',
  _historyPath(channelId),
  (_) => jsonResponse(newestFirst),
);

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
        await session.dispatch('READY', _readyWithGuildOut());

        expect(_spaceRow(_guildId), findsOneWidget);
        expect(_channelRow(_channelId), findsOneWidget);
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        await session.dispatch('GUILD_CREATE', _defaultGuild());

        expect(_spaceRow(_guildId), findsOneWidget);
        expect(session.messageRow('900000000000000001'), findsOneWidget);
      },
      routes: _oneMessage,
    );

    testSession('a guild one READY drops is back when a later READY names it', (
      tester,
      session,
    ) async {
      await session.openChannel(_channelId);

      await _loseSession(session);
      await session.dispatch('READY', _readyWithNoGuilds());
      expect(_spaceRow(_guildId), findsNothing);

      await _identifyAgain(session);

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
        (_guildOf(ready)['channels']! as List).add(
          rawChannel(id: _newChannelId, name: 'new'),
        );

        await session.dispatch('READY', ready, settle: false);
        await session.dispatch(
          'MESSAGE_CREATE',
          _message('900000000000000009', _newChannelId, 9, guildId: _guildId),
        );

        final name = tester.widget<Text>(find.text('new'));
        expect(name.style?.fontWeight, FontWeight.w500);
      },
    );
  });

  group('history after a re-identify', () {
    testSession(
      'messages sent during the outage appear in the active channel, and the '
      'timeline stays up while they load',
      (tester, session) async {
        await session.openChannel(_channelId);
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        final missed = Completer<DiscordHttpResponse>();
        session.transport.on(
          'GET',
          _historyPath(_channelId),
          (_) => missed.future,
        );
        await _identifyAgain(session);

        expect(find.byType(ChannelLoadingView), findsNothing);
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        missed.complete(
          jsonResponse([
            _guildMessage('900000000000000002', 2),
            _guildMessage('900000000000000001', 1),
          ]),
        );
        await session.settle();

        expect(session.messageRow('900000000000000002'), findsOneWidget);
        expect(session.messageRow('900000000000000001'), findsOneWidget);
      },
      routes: _oneMessage,
    );

    testSession(
      'a message that arrives while the missed page is on its way stays',
      (tester, session) async {
        await session.openChannel(_channelId);
        final missed = Completer<DiscordHttpResponse>();
        session.transport.on(
          'GET',
          _historyPath(_channelId),
          (_) => missed.future,
        );
        await _identifyAgain(session);

        await session.dispatch(
          'MESSAGE_CREATE',
          _guildMessage('900000000000000003', 3),
        );
        missed.complete(
          jsonResponse([
            _guildMessage('900000000000000002', 2),
            _guildMessage('900000000000000001', 1),
          ]),
        );
        await session.settle();

        expect(session.messageRow('900000000000000002'), findsOneWidget);
        expect(session.messageRow('900000000000000003'), findsOneWidget);
      },
      routes: _oneMessage,
    );

    testSession(
      'older messages stay when the page reaches them, and a message deleted '
      'in the outage goes',
      (tester, session) async {
        await session.openChannel(_channelId);
        expect(session.messageRow('900000000000000004'), findsOneWidget);

        _historyAnswers(session, _channelId, [
          _guildMessage('900000000000000005', 5),
          _guildMessage('900000000000000003', 3),
        ]);
        await _identifyAgain(session);

        expect(session.messageRow('900000000000000001'), findsOneWidget);
        expect(session.messageRow('900000000000000003'), findsOneWidget);
        expect(session.messageRow('900000000000000004'), findsNothing);
        expect(session.messageRow('900000000000000005'), findsOneWidget);
      },
      routes: (transport) => transport.on(
        'GET',
        _historyPath(_channelId),
        (_) => jsonResponse([
          _guildMessage('900000000000000004', 4),
          _guildMessage('900000000000000003', 3),
          _guildMessage('900000000000000001', 1),
        ]),
      ),
    );

    testSession(
      'a page that does not reach the held messages replaces them, so no hole '
      'stays',
      (tester, session) async {
        await session.openChannel(_channelId);
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        _historyAnswers(session, _channelId, [
          _guildMessage('900000000000000050', 50),
        ]);
        await _identifyAgain(session);

        expect(session.messageRow('900000000000000050'), findsOneWidget);
        expect(session.messageRow('900000000000000001'), findsNothing);
      },
      routes: _oneMessage,
    );

    testSession(
      'a message right behind READY stays when the page is empty',
      (tester, session) async {
        await session.openChannel(_channelId);
        _historyAnswers(session, _channelId, []);

        await _loseSession(session);
        await session.dispatch(
          'READY',
          SessionHarness.defaultReady(),
          settle: false,
        );
        await session.dispatch(
          'MESSAGE_CREATE',
          _guildMessage('900000000000000051', 51),
          settle: false,
        );
        await session.settle();

        expect(session.messageRow('900000000000000051'), findsOneWidget);
      },
    );

    testSession(
      'the missed messages are acked with the window in focus, and stay unread '
      'with it away',
      (tester, session) async {
        await session.openChannel(_channelId);

        Future<void> identifyAgainNaming(String id, int minute) async {
          _historyAnswers(session, _channelId, [_guildMessage(id, minute)]);
          await _loseSession(session);
          await session.dispatch('READY', _readyNamingLatest(id));
          // An ack waits out its debounce.
          await tester.pump(const Duration(seconds: 4));
          await session.settle();
        }

        bool acked(String id) => session.transport.requests.any(
          (request) =>
              request.method == 'POST' &&
              request.uri.path.endsWith('/messages/$id/ack'),
        );

        await identifyAgainNaming('900000000000000002', 2);
        expect(acked('900000000000000002'), isTrue);

        session.blurWindow();
        await identifyAgainNaming('900000000000000003', 3);

        expect(session.messageRow('900000000000000003'), findsOneWidget);
        expect(acked('900000000000000003'), isFalse);
      },
    );

    testSession(
      'another held channel asks for nothing until it opens, and then shows '
      'what was missed',
      (tester, session) async {
        await session.openChannel(_otherChannelId);
        await session.openChannel(_channelId);
        expect(_historyRequests(session, _otherChannelId), 1);

        _historyAnswers(session, _otherChannelId, [
          _otherMessage('900000000000000002', 2),
        ]);
        await _identifyAgain(session);
        expect(_historyRequests(session, _otherChannelId), 1);

        await session.openChannel(_otherChannelId);

        expect(_historyRequests(session, _otherChannelId), 2);
        expect(session.messageRow('900000000000000002'), findsOneWidget);
      },
    );

    testSession(
      'a channel with unread messages and a long outage holds no hole when it '
      'opens',
      (tester, session) async {
        await session.openChannel(_otherChannelId);
        await session.openChannel(_channelId);
        await session.dispatch(
          'MESSAGE_CREATE',
          _otherMessage('900000000000000001', 1),
        );

        _historyAnswers(session, _otherChannelId, [
          _otherMessage('900000000000000050', 50),
        ]);
        await _identifyAgain(session);
        await session.openChannel(_otherChannelId);

        expect(session.messageRow('900000000000000050'), findsOneWidget);
        expect(session.messageRow('900000000000000001'), findsNothing);
      },
    );

    testSession(
      'a failed fetch keeps the timeline, with no error view, and opening the '
      'channel again retries',
      (tester, session) async {
        await session.openChannel(_channelId);
        _historyFails(session);
        await _identifyAgain(session);

        expect(find.byType(ChannelFailureView), findsNothing);
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        _historyAnswers(session, _channelId, [
          _guildMessage('900000000000000002', 2),
          _guildMessage('900000000000000001', 1),
        ]);
        await session.openChannel(_channelId);

        expect(session.messageRow('900000000000000002'), findsOneWidget);
      },
      routes: _oneMessage,
    );

    testSession(
      'an active channel whose guild was out fetches when the guild comes back',
      (tester, session) async {
        await session.openChannel(_channelId);
        _historyFails(session);
        await _loseSession(session);
        await session.dispatch('READY', _readyWithGuildOut());

        _historyAnswers(session, _channelId, [
          _guildMessage('900000000000000002', 2),
          _guildMessage('900000000000000001', 1),
        ]);
        await session.dispatch('GUILD_CREATE', _defaultGuild());

        expect(session.messageRow('900000000000000002'), findsOneWidget);
      },
      routes: _oneMessage,
    );
  });

  group('a channel that comes back', () {
    testSession('a deleted channel loads its history again when it returns', (
      tester,
      session,
    ) async {
      await session.openChannel(_otherChannelId);
      await session.openChannel(_channelId);
      expect(_historyRequests(session, _otherChannelId), 1);

      final other = {
        ...rawChannel(id: _otherChannelId, name: 'random'),
        'guild_id': _guildId,
      };
      await session.dispatch('CHANNEL_DELETE', other);
      expect(_channelRow(_otherChannelId), findsNothing);
      await session.dispatch('CHANNEL_CREATE', other);
      await session.openChannel(_otherChannelId);

      expect(_historyRequests(session, _otherChannelId), 2);
    });

    testSession(
      'a guild READY dropped loads its channels again when it returns',
      (tester, session) async {
        await session.openChannel(_channelId);
        expect(session.messageRow('900000000000000001'), findsOneWidget);

        await _loseSession(session);
        await session.dispatch('READY', _readyWithNoGuilds());
        expect(_spaceRow(_guildId), findsNothing);
        await session.dispatch('GUILD_CREATE', _defaultGuild());
        await session.openChannel(_channelId);

        expect(session.messageRow('900000000000000001'), findsOneWidget);
      },
      routes: (transport) {
        _oneMessage(transport);
        // A guild gained afresh asks for its read state.
        transport.on(
          'GET',
          '/api/v9/guilds/$_guildId/read-state',
          (_) => jsonResponse(const <String, Object?>{}),
        );
      },
    );
  });
}
