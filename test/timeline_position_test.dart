import 'dart:async';

import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/presentation/widgets/chat_scope.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';

import 'support/channel_history_fixture.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _channelMessagesPath = ChannelHistoryFixture.messagesPath;

/// What a full page holds. A full page tells the client that more history
/// exists, so it can ask for an older one.
const _pageSize = 100;

/// The first message of the channel's newest page.
const _firstHeld = 100;
const _newestHeld = _firstHeld + _pageSize - 1;

const _idOf = ChannelHistoryFixture.idOf;
const _rawMessage = ChannelHistoryFixture.message;
const _page = ChannelHistoryFixture.page;

/// How long a plain ack waits before it goes out.
const _ackDebounce = Duration(seconds: 3);

/// The first unread message of a channel opened with [_readyWithUnread].
const _firstUnread = _firstHeld + 50;

Map<String, Object?> _readyWithUnread({
  int firstUnread = _firstUnread,
  int newest = _newestHeld,
}) => ChannelHistoryFixture.readyWithUnread(
  firstUnread: firstUnread,
  newest: newest,
);

Finder get _newLine => find.byKey(const ValueKey('unread-message-boundary'));

/// The NEW line sits directly above the row of the message at [index].
void _expectNewLineAbove(
  WidgetTester tester,
  SessionHarness session,
  int index,
) {
  expect(_newLine, findsOneWidget);
  expect(
    tester.getBottomLeft(_newLine).dy,
    tester.getTopLeft(session.messageRow(_idOf(index))).dy,
  );
}

/// Waits for the plain ack, and returns the messages acked in the channel.
Future<List<String>> _ackedMessages(
  WidgetTester tester,
  SessionHarness session,
) async {
  await tester.pump(_ackDebounce);
  await session.settle();
  return [
    for (final request in session.transport.requests)
      if (request.method == 'POST' && request.uri.path.endsWith('/ack'))
        request.uri.pathSegments[5],
  ];
}

/// Answers with the newest page, and with the page before it when asked.
void _routeHistory(FakeDiscordTransport transport) {
  transport.on('GET', _channelMessagesPath, (request) {
    final older = request.uri.queryParameters['before'] != null;
    return jsonResponse(
      older ? _page(0, _firstHeld) : _page(_firstHeld, _pageSize),
    );
  });
}

Future<void> _arrive(SessionHarness session, int index) =>
    session.dispatch('MESSAGE_CREATE', _rawMessage(index));

/// Scrolls the timeline with a drag on a row that is on screen. A positive
/// [dy] moves toward older messages.
Future<void> _drag(
  WidgetTester tester,
  SessionHarness session,
  double dy,
) async {
  final list = find.ancestor(
    of: find.byType(MessageItem),
    matching: find.byType(CustomScrollView),
  );
  await tester.drag(list.first, Offset(0, dy));
  await session.settle();
}

/// Reads where the first row on screen sits, for a later check that it stayed.
({Finder row, double top}) _rowOnScreen(
  WidgetTester tester,
  SessionHarness session,
) {
  for (var index = _newestHeld; index >= 0; index--) {
    final row = session.messageRow(_idOf(index));
    if (row.evaluate().isEmpty) continue;
    final top = tester.getTopLeft(row).dy;
    if (top > 200 && top < 500) return (row: row, top: top);
  }
  throw StateError('No message row sits in the middle of the screen.');
}

/// The newest message's row ends above the composer, where the reader sees it.
void _expectVisible(WidgetTester tester, SessionHarness session, int index) {
  final row = session.messageRow(_idOf(index));
  expect(row, findsOneWidget);
  expect(
    tester.getBottomLeft(row).dy,
    lessThanOrEqualTo(
      tester.getTopLeft(find.byKey(const ValueKey('message-composer'))).dy,
    ),
  );
}

void main() {
  group('a reader scrolled up holds still when messages arrive', () {
    testSession('in a channel opened at its end', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _drag(tester, session, 800);
      final watched = _rowOnScreen(tester, session);

      for (var index = _newestHeld + 1; index <= _newestHeld + 5; index++) {
        await _arrive(session, index);
        expect(tester.getTopLeft(watched.row).dy, watched.top);
      }
    }, routes: _routeHistory);
  });

  group('a reader at the end sees new messages with no scrolling', () {
    testSession('in a channel opened at its end', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      for (var index = _newestHeld + 1; index <= _newestHeld + 3; index++) {
        await _arrive(session, index);
        _expectVisible(tester, session, index);
      }
    }, routes: _routeHistory);
  });

  testSession('sending while scrolled up lands on the sent message', (
    tester,
    session,
  ) async {
    session.transport.on('POST', _channelMessagesPath, (_) {
      return jsonResponse(
        _rawMessage(_newestHeld + 1, authorId: SessionHarness.currentUserId),
      );
    });
    await session.openChannel(SessionHarness.channelId);
    await _drag(tester, session, 800);
    expect(session.messageRow(_idOf(_newestHeld)), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'Message ${_newestHeld + 1}',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await session.settle();

    _expectVisible(tester, session, _newestHeld + 1);
  }, routes: _routeHistory);

  testSession(
    'a message that arrives while the window is away moves nothing',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _drag(tester, session, 800);
      final watched = _rowOnScreen(tester, session);
      final chat = ChatScope.read(tester.element(watched.row));

      chat.setApplicationActive(false);
      await _arrive(session, _newestHeld + 1);
      chat.setApplicationActive(true);
      await session.settle();

      expect(tester.getTopLeft(watched.row).dy, watched.top);
    },
    routes: _routeHistory,
  );

  group('a channel opened unread', () {
    Future<void> open(SessionHarness session) =>
        session.openChannel(SessionHarness.channelId);

    testSession(
      'shows the NEW line at the first unread message, after the ack went out',
      (tester, session) async {
        await open(session);

        _expectNewLineAbove(tester, session, _firstUnread);
        expect(await _ackedMessages(tester, session), [_idOf(_newestHeld)]);
        _expectNewLineAbove(tester, session, _firstUnread);
      },
      ready: _readyWithUnread(),
      routes: _routeHistory,
    );

    testSession(
      'opens at that message and not at the newest',
      (tester, session) async {
        await open(session);

        final top = tester.getTopLeft(session.messageRow(_idOf(_firstUnread)));
        expect(top.dy, inInclusiveRange(60, 300));
        expect(session.messageRow(_idOf(_newestHeld)), findsNothing);
        expect(find.byKey(const ValueKey('jump-to-unread')), findsNothing);
      },
      ready: _readyWithUnread(),
      routes: _routeHistory,
    );

    testSession(
      'holds still for a reader scrolled up when messages arrive',
      (tester, session) async {
        await open(session);
        await _drag(tester, session, 300);
        final watched = _rowOnScreen(tester, session);

        for (var index = _newestHeld + 1; index <= _newestHeld + 5; index++) {
          await _arrive(session, index);
          expect(tester.getTopLeft(watched.row).dy, watched.top);
        }
      },
      ready: _readyWithUnread(),
      routes: _routeHistory,
    );

    testSession(
      'follows new messages once the reader reaches the end',
      (tester, session) async {
        await open(session);
        for (var drag = 0; drag < 20; drag++) {
          await _drag(tester, session, -800);
        }
        _expectVisible(tester, session, _newestHeld);

        for (var index = _newestHeld + 1; index <= _newestHeld + 3; index++) {
          await _arrive(session, index);
          _expectVisible(tester, session, index);
        }
      },
      ready: _readyWithUnread(),
      routes: _routeHistory,
    );

    testSession(
      'keeps the NEW line when only the channel pointer moves',
      (tester, session) async {
        await open(session);

        await session.dispatch('PASSIVE_UPDATE_V2', {
          'channels': [
            {
              'id': SessionHarness.channelId,
              'last_message_id': _idOf(_newestHeld + 1),
            },
          ],
        });

        _expectNewLineAbove(tester, session, _firstUnread);
      },
      ready: _readyWithUnread(),
      routes: _routeHistory,
    );

    testSession(
      'moves nothing when the window blurs and comes back over the boundary',
      (tester, session) async {
        await open(session);
        final watched = _rowOnScreen(tester, session);

        session.blurWindow();
        await session.settle();
        expect(tester.getTopLeft(watched.row).dy, watched.top);
        _expectNewLineAbove(tester, session, _firstUnread);

        session.focusWindow();
        await session.settle();
        expect(tester.getTopLeft(watched.row).dy, watched.top);
        _expectNewLineAbove(tester, session, _firstUnread);
      },
      ready: _readyWithUnread(),
      routes: _routeHistory,
    );
  });

  group('a channel opened unread after a relaunch, with a cached page', () {
    /// Puts the newest page in the cache, then relaunches with the channel's
    /// refresh held open until the returned completer finishes.
    Future<Completer<DiscordHttpResponse>> relaunch(
      SessionHarness session,
      Map<String, Object?> ready,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      final refresh = Completer<DiscordHttpResponse>();
      session.transport.on('GET', _channelMessagesPath, (_) => refresh.future);
      await session.relaunch(ready: ready);
      await session.openChannel(SessionHarness.channelId);
      return refresh;
    }

    testSession(
      'opens on the boundary at once when the cache holds it',
      (tester, session) async {
        final refresh = await relaunch(session, _readyWithUnread());

        _expectNewLineAbove(tester, session, _firstUnread);

        refresh.complete(jsonResponse(_page(_firstHeld, _pageSize)));
        await session.settle();

        _expectNewLineAbove(tester, session, _firstUnread);
      },
      routes: _routeHistory,
      onDisk: true,
    );

    testSession(
      'waits for the refresh when every cached message is older than the boundary',
      (tester, session) async {
        final refresh = await relaunch(
          session,
          _readyWithUnread(
            firstUnread: _newestHeld + 1,
            newest: _newestHeld + 60,
          ),
        );

        expect(session.messageRow(_idOf(_newestHeld)), findsNothing);

        refresh.complete(jsonResponse(_page(_firstHeld + 60, _pageSize)));
        await session.settle();

        _expectNewLineAbove(tester, session, _newestHeld + 1);
        expect(session.messageRow(_idOf(_newestHeld + 60)), findsNothing);
      },
      routes: _routeHistory,
      onDisk: true,
    );

    testSession(
      'shows the cached page if the refresh fails',
      (tester, session) async {
        final refresh = await relaunch(
          session,
          _readyWithUnread(
            firstUnread: _newestHeld + 1,
            newest: _newestHeld + 60,
          ),
        );

        refresh.complete(jsonResponse({'message': 'Nope'}, statusCode: 403));
        await session.settle();

        expect(session.messageRow(_idOf(_newestHeld)), findsOneWidget);
      },
      routes: _routeHistory,
      onDisk: true,
    );
  });

  group('a channel opened read', () {
    testSession(
      'on refocus shows the NEW line at the first message that came while away',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        expect(_newLine, findsNothing);

        session.blurWindow();
        await session.settle();
        await _arrive(session, _newestHeld + 1);
        await _arrive(session, _newestHeld + 2);
        session.focusWindow();
        await session.settle();

        _expectNewLineAbove(tester, session, _newestHeld + 1);
        expect(
          await _ackedMessages(tester, session),
          contains(_idOf(_newestHeld + 2)),
        );
        _expectNewLineAbove(tester, session, _newestHeld + 1);
      },
      routes: _routeHistory,
    );

    testSession('on refocus holds still for a reader scrolled up', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _drag(tester, session, 800);
      final watched = _rowOnScreen(tester, session);

      session.blurWindow();
      await _arrive(session, _newestHeld + 1);
      session.focusWindow();
      await session.settle();

      expect(tester.getTopLeft(watched.row).dy, watched.top);
      expect(find.byKey(const ValueKey('jump-to-unread')), findsOneWidget);
    }, routes: _routeHistory);

    testSession('after another device read it has no NEW line', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.otherChannelId);
      await session.dispatch('MESSAGE_CREATE', _rawMessage(_newestHeld + 1));
      await session.dispatch('MESSAGE_ACK', {
        'channel_id': SessionHarness.channelId,
        'message_id': _idOf(_newestHeld + 1),
        'version': 2,
      });
      session.transport.on(
        'GET',
        _channelMessagesPath,
        (_) => jsonResponse(_page(_firstHeld + 1, _pageSize)),
      );

      await tester.tap(
        find.byKey(const ValueKey('channel-${SessionHarness.channelId}')),
      );
      await session.settle();

      expect(_newLine, findsNothing);
      _expectVisible(tester, session, _newestHeld + 1);
    });
  });

  group('markdown parses per appended message', () {
    // Only a body with markup is parsed.
    String marked(int index) => '**Message $index**';

    void routeMarkedHistory(FakeDiscordTransport transport) => transport.on(
      'GET',
      _channelMessagesPath,
      (_) => jsonResponse([
        for (var index = _newestHeld; index >= _firstHeld; index--)
          _rawMessage(index, content: marked(index)),
      ]),
    );

    testSession(
      'one for the new message and none for the rows on screen',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        final before = _parsedMarkdown(tester);
        expect(before, isNotEmpty);

        await session.dispatch(
          'MESSAGE_CREATE',
          _rawMessage(_newestHeld + 1, content: marked(_newestHeld + 1)),
        );

        expect(_parsesSince(before, _parsedMarkdown(tester)), 1);
      },
      routes: routeMarkedHistory,
    );

    testSession('none when a rebuild adds no message', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      final before = _parsedMarkdown(tester);
      expect(before, isNotEmpty);

      // An edit to a row that is not mounted rebuilds the list and adds no row.
      await session.dispatch(
        'MESSAGE_UPDATE',
        _rawMessage(_firstHeld, content: marked(_firstHeld)),
      );

      expect(_parsesSince(before, _parsedMarkdown(tester)), 0);
    }, routes: routeMarkedHistory);

    testSession('none for a body with no markup', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await _arrive(session, _newestHeld + 1);

      expect(session.messageRow(_idOf(_newestHeld + 1)), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);
    }, routes: _routeHistory);
  });

  testSession('an older page loads with no scroll jump', (
    tester,
    session,
  ) async {
    final olderPage = Completer<DiscordHttpResponse>();
    session.transport.on('GET', _channelMessagesPath, (request) {
      return request.uri.queryParameters['before'] == null
          ? jsonResponse(_page(_firstHeld, _pageSize))
          : olderPage.future;
    });
    await session.openChannel(SessionHarness.channelId);
    await _arrive(session, _newestHeld + 1);
    bool askedForOlder() => session.transport.requests.any(
      (request) => request.uri.queryParameters['before'] != null,
    );
    for (var drag = 0; drag < 20 && !askedForOlder(); drag++) {
      await _drag(tester, session, 800);
    }
    expect(askedForOlder(), isTrue);
    final watched = _rowOnScreen(tester, session);

    olderPage.complete(jsonResponse(_page(0, _firstHeld)));
    await session.settle();

    expect(session.messageRow(_idOf(_firstHeld - 1)), findsOneWidget);
    expect(tester.getTopLeft(watched.row).dy, watched.top);
  });
}

/// What each mounted markdown body drew, by its state. Parsing builds a new
/// text widget, so a body that kept its text widget did not parse again.
Map<State, Widget> _parsedMarkdown(WidgetTester tester) {
  final parsed = <State, Widget>{};
  for (final element in find.byType(MarkdownBody).evaluate()) {
    Widget? text;
    void visit(Element child) {
      if (text != null) return;
      if (child.widget is RichText || child.widget is SelectableText) {
        text = child.widget;
        return;
      }
      child.visitChildren(visit);
    }

    visit(element);
    if (text != null) parsed[(element as StatefulElement).state] = text!;
  }
  return parsed;
}

/// New bodies parsed once, and kept bodies with a new text widget parsed again.
int _parsesSince(Map<State, Widget> before, Map<State, Widget> after) => after
    .entries
    .where(
      (entry) =>
          !before.containsKey(entry.key) ||
          !identical(before[entry.key], entry.value),
    )
    .length;
