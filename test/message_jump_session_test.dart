import 'dart:async';

import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/channel_history_fixture.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messagesPath = ChannelHistoryFixture.messagesPath;
const _idOf = ChannelHistoryFixture.idOf;
const _page = ChannelHistoryFixture.page;

/// The channel holds messages 0 to 199, and opens on its newest page of 100.
const _newest = 199;
const _newestPageStart = 100;

/// Far outside the newest page.
const _old = 40;

String _linkTo(int index) =>
    'https://discord.com/channels/${SessionHarness.guildId}/${SessionHarness.channelId}/${_idOf(index)}';

/// Answers as Discord does: 50 messages either side of an around anchor, the
/// page before a before cursor, and otherwise the newest page. [newest] is the
/// message the channel has reached.
void _routeHistory(FakeDiscordTransport transport, {int newest = _newest}) {
  transport.on('GET', _messagesPath, (request) {
    final around = request.uri.queryParameters['around'];
    final before = request.uri.queryParameters['before'];
    if (around != null) {
      final anchor = ChannelHistoryFixture.indexOf(around);
      final first = anchor < 50 ? 0 : anchor - 50;
      final last = anchor + 49 > newest ? newest : anchor + 49;
      return jsonResponse(_page(first, last - first + 1));
    }
    if (before != null) {
      final end = ChannelHistoryFixture.indexOf(before);
      final first = end < 100 ? 0 : end - 100;
      return jsonResponse(_page(first, end - first));
    }
    return jsonResponse(_page(newest - 99, 100));
  });
}

/// Follows a message link that somebody just posted, which is on screen at the
/// end of the conversation.
Future<void> _followLinkTo(
  WidgetTester tester,
  SessionHarness session,
  int target, {
  required int postedAs,
}) async {
  final link = _linkTo(target);
  await session.dispatch(
    'MESSAGE_CREATE',
    ChannelHistoryFixture.message(postedAs, content: link),
  );
  final topLeft = tester.getTopLeft(find.text(link, findRichText: true));
  await tester.tapAt(topLeft + const Offset(20, 8));
  await session.settle();
}

List<String> _queriesWith(SessionHarness session, String parameter) => [
  for (final request in session.transport.requests)
    if (request.method == 'GET' &&
        request.uri.path == _messagesPath &&
        request.uri.queryParameters[parameter] != null)
      request.uri.queryParameters[parameter]!,
];

void main() {
  group('jumping to a message the loaded channel does not hold', () {
    testSession('fetches around it and lands on it', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      expect(session.messageRow(_idOf(_old)), findsNothing);

      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);

      expect(_queriesWith(session, 'around'), [_idOf(_old)]);
      final row = session.messageRow(_idOf(_old));
      expect(row, findsOneWidget);
      expect(tester.getTopLeft(row).dy, inInclusiveRange(0, 400));
    }, routes: _routeHistory);

    testSession('highlights it, and the highlight fades out', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);

      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);

      expect(_rowColour(tester, session, _old).a, greaterThan(0));

      await tester.pump(const Duration(seconds: 3));

      expect(_rowColour(tester, session, _old).a, 0);
    }, routes: _routeHistory);

    testSession('lands again after the reader scrolled away', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _search(tester, session, _old);
      await _jumpToResult(tester, session, _old);
      await _scrollTimeline(tester, session, -1500);
      expect(session.messageRow(_idOf(_old)), findsNothing);

      await _jumpToResult(tester, session, _old);

      expect(
        tester.getTopLeft(session.messageRow(_idOf(_old))).dy,
        inInclusiveRange(0, 400),
      );
    }, routes: _routeHistory);

    testSession('from a pin notice lands on the pinned message', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch(
        'MESSAGE_CREATE',
        ChannelHistoryFixture.message(_newest + 1)
          ..['type'] = 6
          ..['message_reference'] = {
            'channel_id': SessionHarness.channelId,
            'message_id': _idOf(_old),
          },
      );
      await tester.tap(find.text('View message'));
      await session.settle();

      expect(_queriesWith(session, 'around'), [_idOf(_old)]);
      expect(session.messageRow(_idOf(_old)), findsOneWidget);
      expect(_rowColour(tester, session, _old).a, greaterThan(0));
    }, routes: _routeHistory);

    testSession(
      'that fails keeps the reader where they were and says so',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        session.transport.on(
          'GET',
          _messagesPath,
          (_) => jsonResponse({'message': 'Unknown'}, statusCode: 404),
        );

        await _followLinkTo(tester, session, _old, postedAs: _newest + 1);

        expect(session.messageRow(_idOf(_newest + 1)), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      },
      routes: _routeHistory,
    );

    testSession('whose message is gone does the same', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      session.transport.on(
        'GET',
        _messagesPath,
        (_) => jsonResponse(_page(_old + 1, 60)),
      );

      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);

      expect(session.messageRow(_idOf(_newest + 1)), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    }, routes: _routeHistory);

    testSession('drops a late older page of the window it left', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      final olderPage = Completer<DiscordHttpResponse>();
      session.transport.on('GET', _messagesPath, (request) {
        if (request.uri.queryParameters['before'] != null) {
          return olderPage.future;
        }
        return jsonResponse(_page(0, 90));
      });
      for (var drag = 0; drag < 20; drag++) {
        if (_queriesWith(session, 'before').isNotEmpty) break;
        await _scrollTimeline(tester, session, 1500);
      }
      expect(_queriesWith(session, 'before'), isNotEmpty);
      await _search(tester, session, _old);

      await _jumpToResult(tester, session, _old);
      olderPage.complete(jsonResponse(_page(0, _newestPageStart)));
      await session.settle();
      await _scrollTimeline(tester, session, -20000);

      // The window ends at message 89. The late page reached 99.
      expect(session.messageRow(_idOf(89)), findsOneWidget);
      expect(session.messageRow(_idOf(99)), findsNothing);
    }, routes: _routeHistory);
  });

  group('a re-identify', () {
    testSession('leaves the reader in an old window, and Jump to present shows '
        'what was missed', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _search(tester, session, _old);
      await _jumpToResult(tester, session, _old);
      expect(session.messageRow(_idOf(_old)), findsOneWidget);

      _routeHistory(session.transport, newest: _newest + 1);
      session.socket.receive(const {'op': 9, 'd': false});
      await session.settle();
      await session.dispatch('READY', SessionHarness.defaultReady());

      expect(session.messageRow(_idOf(_old)), findsOneWidget);
      expect(find.byKey(const ValueKey('jump-to-present')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('jump-to-present')));
      await session.settle();

      expect(session.messageRow(_idOf(_newest + 1)), findsOneWidget);
    }, routes: _routeHistory);

    testSession(
      'during a catch-up does not undo a jump made meanwhile',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _search(tester, session, _old);

        final newestPage = Completer<DiscordHttpResponse>();
        session.transport.on('GET', _messagesPath, (request) {
          return request.uri.queryParameters['around'] == null
              ? newestPage.future
              : jsonResponse(_page(_old - 50, 100));
        });
        session.socket.receive(const {'op': 9, 'd': false});
        await session.settle();
        await session.dispatch('READY', SessionHarness.defaultReady());

        await _jumpToResult(tester, session, _old);
        newestPage.complete(jsonResponse(_page(_newestPageStart + 1, 100)));
        await session.settle();

        expect(session.messageRow(_idOf(_old)), findsOneWidget);
        expect(find.byKey(const ValueKey('jump-to-present')), findsOneWidget);
      },
      routes: _routeHistory,
    );
  });

  group('a jump while another load is running', () {
    testSession('takes the place of a plain load in flight', (
      tester,
      session,
    ) async {
      final plain = Completer<DiscordHttpResponse>();
      session.transport.on('GET', _messagesPath, (request) {
        return request.uri.queryParameters['around'] == null
            ? plain.future
            : jsonResponse(_page(_old - 50, 100));
      });
      // Tapping the server opens its first channel, whose page does not come.
      await tester.tap(
        find.byKey(const ValueKey('space-${SessionHarness.guildId}')),
      );
      await session.settle();
      await _search(tester, session, _old);

      await _jumpToResult(tester, session, _old);
      plain.complete(jsonResponse(_page(_newestPageStart, 100)));
      await session.settle();

      expect(session.messageRow(_idOf(_old)), findsOneWidget);
      expect(find.byKey(const ValueKey('jump-to-present')), findsOneWidget);
    });

    testSession('to a held message drops a window still on its way', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _search(tester, session, _old);
      final window = Completer<DiscordHttpResponse>();
      session.transport.on('GET', _messagesPath, (_) => window.future);
      await _jumpToResult(tester, session, _old);

      await _search(tester, session, _newest - 5);
      await _jumpToResult(tester, session, _newest - 5);
      window.complete(jsonResponse(_page(_old - 50, 100)));
      await session.settle();

      expect(session.messageRow(_idOf(_newest - 5)), findsOneWidget);
      expect(session.messageRow(_idOf(_old)), findsNothing);
    }, routes: _routeHistory);
  });

  group('a channel with more than a page unread', () {
    final backlog = ChannelHistoryFixture.readyWithUnread(
      firstUnread: _old,
      newest: _newest,
    );

    testSession(
      'opens on the true first unread message',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        _expectOpenedOnNewLine(tester, session, _old);
      },
      ready: backlog,
      routes: _routeHistory,
    );

    testSession(
      'a cached page does not keep it from the true one',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        // Left on the DM space, so the channel opens by the tap below and not at
        // launch.
        await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
        await session.settle();
        await session.relaunch(ready: backlog);
        final newestPage = Completer<DiscordHttpResponse>();
        session.transport.on('GET', _messagesPath, (request) {
          return request.uri.queryParameters['around'] == null
              ? newestPage.future
              : jsonResponse(_page(_old - 50 < 0 ? 0 : _old - 50, 90));
        });

        // The list opens on the cached page while Discord is asked.
        await tester.tap(
          find.byKey(const ValueKey('space-${SessionHarness.guildId}')),
        );
        await session.settle();
        expect(session.messageRow(_idOf(_newestPageStart)), findsOneWidget);
        newestPage.complete(jsonResponse(_page(_newestPageStart, 100)));
        await session.settle();

        _expectOpenedOnNewLine(tester, session, _old);
      },
      onDisk: true,
      routes: _routeHistory,
    );

    testSession(
      'jump to present still reaches the newest message',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await tester.tap(find.byKey(const ValueKey('jump-to-present')));
        await session.settle();

        _expectAtPresent(tester, session, _newest);
      },
      ready: backlog,
      routes: _routeHistory,
    );

    testSession('stays on the newest page if the older one fails', (
      tester,
      session,
    ) async {
      session.transport.on('GET', _messagesPath, (request) {
        return request.uri.queryParameters['around'] != null
            ? jsonResponse({'message': 'Unknown'}, statusCode: 404)
            : jsonResponse(_page(_newestPageStart, 100));
      });

      await session.openChannel(SessionHarness.channelId);

      expect(session.messageRow(_idOf(_newestPageStart)), findsOneWidget);
    }, ready: backlog);

    testSession('stays on the newest page if the read message is gone', (
      tester,
      session,
    ) async {
      session.transport.on('GET', _messagesPath, (request) {
        return request.uri.queryParameters['around'] != null
            ? jsonResponse(_page(_old, 60))
            : jsonResponse(_page(_newestPageStart, 100));
      });

      await session.openChannel(SessionHarness.channelId);

      _expectOpenedOnNewLine(tester, session, _newestPageStart);
    }, ready: backlog);
  });

  group('a channel with less than a page unread', () {
    testSession(
      'asks for no second page',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        expect(_queriesWith(session, 'around'), isEmpty);
      },
      ready: ChannelHistoryFixture.readyWithUnread(
        firstUnread: _newest - 5,
        newest: _newest,
      ),
      routes: _routeHistory,
    );
  });

  group('an around page and the start of history', () {
    testSession(
      'a short page in a loaded channel can still load older',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        session.transport.on('GET', _messagesPath, (request) {
          return request.uri.queryParameters['before'] != null
              ? jsonResponse(_page(0, _old - 10))
              : jsonResponse(_page(_old - 10, 60));
        });

        await _followLinkTo(tester, session, _old, postedAs: _newest + 1);
        for (var drag = 0; drag < 20; drag++) {
          if (_queriesWith(session, 'before').isNotEmpty) break;
          await _scrollTimeline(tester, session, 800);
        }

        expect(_queriesWith(session, 'before'), [_idOf(_old - 10)]);
      },
      routes: _routeHistory,
    );

    testSession('a short page in a channel not yet opened can too', (
      tester,
      session,
    ) async {
      session.transport.on('GET', _messagesPath, (request) {
        return request.uri.queryParameters['before'] != null
            ? jsonResponse(_page(0, _old - 10))
            : jsonResponse(_page(_old - 10, 60));
      });
      // The session opens on a DM, and the link there leads into the guild.
      final link = _linkTo(_old);
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: _idOf(_newest),
          channelId: SessionHarness.dmChannelId,
          authorId: SessionHarness.friendId,
          content: link,
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(find.text(link, findRichText: true)) +
            const Offset(20, 8),
      );
      await session.settle();
      expect(session.messageRow(_idOf(_old)), findsOneWidget);
      for (var drag = 0; drag < 20; drag++) {
        if (_queriesWith(session, 'before').isNotEmpty) break;
        await _scrollTimeline(tester, session, 800);
      }

      expect(_queriesWith(session, 'before'), [_idOf(_old - 10)]);
    });
  });

  group('jump to present from an old window', () {
    testSession('lands on the newest message', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);

      _routeHistory(session.transport, newest: _newest + 1);
      await tester.tap(find.byKey(const ValueKey('jump-to-present')));
      await session.settle();

      _expectAtPresent(tester, session, _newest + 1);
    }, routes: _routeHistory);

    testSession('is offered at the end of an old window too', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);

      await _scrollTimeline(tester, session, -20000);

      expect(session.messageRow(_idOf(_old + 49)), findsOneWidget);
      expect(find.byKey(const ValueKey('jump-to-present')), findsOneWidget);
    }, routes: _routeHistory);

    testSession('a window that reaches the present needs no way back', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      session.transport.on(
        'GET',
        _messagesPath,
        (_) => jsonResponse(_page(_old, _newest + 2 - _old)),
      );

      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);
      await _scrollTimeline(tester, session, -40000);

      expect(session.messageRow(_idOf(_newest + 1)), findsOneWidget);
      expect(find.byKey(const ValueKey('jump-to-present')), findsNothing);
    }, routes: _routeHistory);

    testSession('coming back to the channel opens on the present', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);

      await tester.tap(
        find.byKey(const ValueKey('channel-${SessionHarness.otherChannelId}')),
      );
      await session.settle();
      _routeHistory(session.transport, newest: _newest + 1);
      await tester.tap(
        find.byKey(const ValueKey('channel-${SessionHarness.channelId}')),
      );
      await session.settle();

      _expectAtPresent(tester, session, _newest + 1);
    }, routes: _routeHistory);
  });

  group('live messages during an old window', () {
    testSession('stay out of it, and show after jump to present', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);

      await session.dispatch(
        'MESSAGE_CREATE',
        ChannelHistoryFixture.message(_newest + 2),
      );
      await _scrollTimeline(tester, session, -20000);
      expect(session.messageRow(_idOf(_old + 49)), findsOneWidget);
      expect(session.messageRow(_idOf(_newest + 2)), findsNothing);

      _routeHistory(session.transport, newest: _newest + 2);
      await tester.tap(find.byKey(const ValueKey('jump-to-present')));
      await session.settle();

      _expectAtPresent(tester, session, _newest + 2);
      expect(session.messageRow(_idOf(_newest + 1)), findsOneWidget);
    }, routes: _routeHistory);

    testSession('one that lands during the load is not lost', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _followLinkTo(tester, session, _old, postedAs: _newest + 1);
      final present = Completer<DiscordHttpResponse>();
      session.transport.on('GET', _messagesPath, (_) => present.future);

      await tester.tap(find.byKey(const ValueKey('jump-to-present')));
      await session.settle();
      await session.dispatch(
        'MESSAGE_CREATE',
        ChannelHistoryFixture.message(_newest + 2),
      );
      present.complete(jsonResponse(_page(_newest - 98, 100)));
      await session.settle();

      _expectAtPresent(tester, session, _newest + 2);
    }, routes: _routeHistory);

    testSession(
      'sending from it lands on the sent message with no gap',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _followLinkTo(tester, session, _old, postedAs: _newest + 1);
        session.transport.on(
          'POST',
          _messagesPath,
          (_) => jsonResponse(
            ChannelHistoryFixture.message(
              _newest + 2,
              authorId: SessionHarness.currentUserId,
            ),
          ),
        );
        _routeHistory(session.transport, newest: _newest + 2);

        await tester.enterText(
          find.byKey(const ValueKey('message-composer')),
          'Message ${_newest + 2}',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await session.settle();

        _expectAtPresent(tester, session, _newest + 2);
        expect(session.messageRow(_idOf(_newest + 1)), findsOneWidget);
      },
      routes: _routeHistory,
    );
  });
}

/// Searches the server for a message, and the result panel lists it.
Future<void> _search(
  WidgetTester tester,
  SessionHarness session,
  int target,
) async {
  session.transport.on(
    'GET',
    '/api/v9/guilds/${SessionHarness.guildId}/messages/search',
    (_) => jsonResponse({
      'total_results': 1,
      'messages': [
        [ChannelHistoryFixture.message(target)],
      ],
    }),
  );
  await tester.enterText(find.byKey(const ValueKey('message-search')), 'hit');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await session.settle();
}

Future<void> _jumpToResult(
  WidgetTester tester,
  SessionHarness session,
  int target,
) async {
  await tester.tap(find.byKey(ValueKey('jump-to-${_idOf(target)}')));
  await session.settle();
}

/// The NEW line sits on screen, directly above the message at [index].
void _expectOpenedOnNewLine(
  WidgetTester tester,
  SessionHarness session,
  int index,
) {
  final row = session.messageRow(_idOf(index));
  expect(row, findsOneWidget);
  expect(tester.getTopLeft(row).dy, inInclusiveRange(0, 400));
  expect(
    tester
        .getBottomLeft(find.byKey(const ValueKey('unread-message-boundary')))
        .dy,
    tester.getTopLeft(row).dy,
  );
}

/// The colour painted behind a message row.
Color _rowColour(WidgetTester tester, SessionHarness session, int index) =>
    tester
        .widget<ColoredBox>(
          find
              .ancestor(
                of: session.messageRow(_idOf(index)),
                matching: find.byType(ColoredBox),
              )
              .first,
        )
        .color;

/// A positive [dy] moves toward older messages.
Future<void> _scrollTimeline(
  WidgetTester tester,
  SessionHarness session,
  double dy,
) async {
  final list = find
      .ancestor(
        of: find.byType(MessageItem),
        matching: find.byType(CustomScrollView),
      )
      .first;
  await tester.drag(list, Offset(0, dy));
  await session.settle();
}

/// The reader sees the newest message, and nothing suggests more below it.
void _expectAtPresent(WidgetTester tester, SessionHarness session, int index) {
  final row = session.messageRow(_idOf(index));
  expect(row, findsOneWidget);
  expect(
    tester.getBottomLeft(row).dy,
    lessThanOrEqualTo(
      tester.getTopLeft(find.byKey(const ValueKey('message-composer'))).dy,
    ),
  );
  expect(find.byKey(const ValueKey('jump-to-present')), findsNothing);
}
