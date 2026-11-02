import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_rest_client.dart';

import 'support/channel_history_fixture.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messagesPath = ChannelHistoryFixture.messagesPath;
const _idOf = ChannelHistoryFixture.idOf;
const _indexOf = ChannelHistoryFixture.indexOf;
const _page = ChannelHistoryFixture.page;
const _message = ChannelHistoryFixture.message;
const _drag = ChannelHistoryFixture.drag;
const _rowOnScreen = ChannelHistoryFixture.rowOnScreen;

/// What a full page holds, which tells the client that more history exists.
const _pageSize = 100;

/// The oldest and newest message of the channel's newest page at the start.
const _firstHeld = 100;
const _newestHeld = _firstHeld + _pageSize - 1;

/// How far back a drag takes the reader, well inside the newest page.
const _dragUp = 1500.0;

/// More than the cap on a channel that is not open.
const _manyArrivals = 250;

/// Answers as Discord does. The newest page ends at [newest], and a page around
/// a message holds that message unless [around] says otherwise.
void _routeHistory(
  FakeDiscordTransport transport, {
  int newest = _newestHeld,
  DiscordHttpResponse Function(int index)? around,
}) {
  transport.on('GET', _messagesPath, (request) {
    final query = request.uri.queryParameters;
    final anchor = query['around'];
    if (anchor != null) {
      final index = _indexOf(anchor);
      return around?.call(index) ?? jsonResponse(_page(index - 25, 50));
    }
    final before = query['before'];
    if (before != null) {
      final end = _indexOf(before);
      return jsonResponse(_page(end - _pageSize, _pageSize));
    }
    return jsonResponse(_page(newest - _pageSize + 1, _pageSize));
  });
}

Future<void> _openOtherChannel(
  WidgetTester tester,
  SessionHarness session,
) async {
  await tester.tap(
    find.byKey(const ValueKey('channel-${SessionHarness.otherChannelId}')),
  );
  await session.settle();
}

Future<void> _returnToChannel(
  WidgetTester tester,
  SessionHarness session,
) async {
  await tester.tap(
    find.byKey(const ValueKey('channel-${SessionHarness.channelId}')),
  );
  await session.settle();
}

/// Sends messages into the channel while the reader is in another one, past the
/// cap, so the channel no longer holds anything from the newest page it had.
Future<void> _arriveMany(SessionHarness session) async {
  for (var index = 1; index <= _manyArrivals; index++) {
    await session.dispatch(
      'MESSAGE_CREATE',
      _message(_newestHeld + index),
      settle: false,
    );
  }
  await session.settle();
}

int _aroundRequests(SessionHarness session) => session.transport.requests
    .where((request) => request.uri.queryParameters['around'] != null)
    .length;

Finder get _jumpToPresent => find.byKey(const ValueKey('jump-to-present'));

void main() {
  testSession('returning to a channel restores the scroll position', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await _drag(tester, session, _dragUp);
    final spot = _rowOnScreen(tester);

    await _openOtherChannel(tester, session);
    await _returnToChannel(tester, session);

    expect(tester.getTopLeft(spot.row).dy, spot.top);
  }, routes: _routeHistory);

  // The first switch goes through the other channel's loading view, which takes
  // the timeline off the screen. The second one keeps it there.
  testSession(
    'so does a second return, from a channel already loaded',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _drag(tester, session, _dragUp);
      final spot = _rowOnScreen(tester);

      await _openOtherChannel(tester, session);
      await _returnToChannel(tester, session);
      await _openOtherChannel(tester, session);
      await _returnToChannel(tester, session);

      expect(tester.getTopLeft(spot.row).dy, spot.top);
    },
    routes: _routeHistory,
  );

  testSession(
    'a restart restores the scroll position',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _drag(tester, session, _dragUp);
      final spot = _rowOnScreen(tester);

      await session.relaunch(ready: SessionHarness.defaultReady());

      expect(tester.getTopLeft(spot.row).dy, spot.top);
    },
    routes: _routeHistory,
    onDisk: true,
  );

  testSession('a new message while away leaves the position alone', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await _drag(tester, session, _dragUp);
    final spot = _rowOnScreen(tester);

    await _openOtherChannel(tester, session);
    await session.dispatch('MESSAGE_CREATE', _message(_newestHeld + 1));
    await _returnToChannel(tester, session);

    expect(tester.getTopLeft(spot.row).dy, spot.top);
    expect(_jumpToPresent, findsOneWidget);
  }, routes: _routeHistory);

  testSession('a reader back at the end comes back to the end', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await _drag(tester, session, _dragUp);
    await _drag(tester, session, -_dragUp * 2);

    await _openOtherChannel(tester, session);
    await _returnToChannel(tester, session);

    expect(_jumpToPresent, findsNothing);
    expect(session.messageRow(_idOf(_newestHeld)), findsOneWidget);
  }, routes: _routeHistory);

  testSession('jump to present replaces the saved position', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await _drag(tester, session, _dragUp);
    await tester.tap(_jumpToPresent);
    await session.settle();

    await _openOtherChannel(tester, session);
    await _returnToChannel(tester, session);

    expect(_jumpToPresent, findsNothing);
    expect(session.messageRow(_idOf(_newestHeld)), findsOneWidget);
  }, routes: _routeHistory);

  group('a position on a message the cap dropped', () {
    testSession('loads the messages around it and restores', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _drag(tester, session, _dragUp);
      final spot = _rowOnScreen(tester);

      await _openOtherChannel(tester, session);
      await _arriveMany(session);
      _routeHistory(session.transport, newest: _newestHeld + _manyArrivals);
      await _returnToChannel(tester, session);

      expect(tester.getTopLeft(spot.row).dy, spot.top);
      expect(_jumpToPresent, findsOneWidget);
    }, routes: _routeHistory);

    testSession('leads back to the present by Jump to present', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _drag(tester, session, _dragUp);

      await _openOtherChannel(tester, session);
      await _arriveMany(session);
      _routeHistory(session.transport, newest: _newestHeld + _manyArrivals);
      await _returnToChannel(tester, session);
      await tester.tap(_jumpToPresent);
      await session.settle();

      expect(
        session.messageRow(_idOf(_newestHeld + _manyArrivals)),
        findsOneWidget,
      );
    }, routes: _routeHistory);

    testSession(
      'that no longer exists opens on the NEW line, with no error',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _drag(tester, session, _dragUp);

        await _openOtherChannel(tester, session);
        await _arriveMany(session);
        final newest = _newestHeld + _manyArrivals;
        // Discord answers with the neighbours of a deleted message.
        _routeHistory(
          session.transport,
          newest: newest,
          around: (index) => jsonResponse(_page(index + 1, 20)),
        );
        await _returnToChannel(tester, session);

        expect(
          find.byKey(const ValueKey('unread-message-boundary')),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsNothing);

        // The position is gone, so a later return does not ask again.
        final asked = _aroundRequests(session);
        await _openOtherChannel(tester, session);
        await _returnToChannel(tester, session);
        expect(_aroundRequests(session), asked);
      },
      routes: _routeHistory,
    );

    testSession(
      'that fails to load opens at the newest message, and tries again later',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _drag(tester, session, _dragUp);
        final spot = _rowOnScreen(tester);

        await _openOtherChannel(tester, session);
        await _arriveMany(session);
        final newest = _newestHeld + _manyArrivals;
        _routeHistory(
          session.transport,
          newest: newest,
          around: (_) => jsonResponse({'message': 'No'}, statusCode: 401),
        );
        await _returnToChannel(tester, session);

        expect(session.messageRow(_idOf(newest)), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);

        _routeHistory(session.transport, newest: newest);
        await _openOtherChannel(tester, session);
        await _returnToChannel(tester, session);

        expect(tester.getTopLeft(spot.row).dy, spot.top);
      },
      routes: _routeHistory,
    );
  });
}
