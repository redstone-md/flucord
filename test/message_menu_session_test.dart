import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/channel_history_fixture.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _idOf = ChannelHistoryFixture.idOf;

final _markUnread = find.byKey(const ValueKey('message-menu-mark-unread'));
final _addReaction = find.byKey(const ValueKey('message-menu-add-reaction'));
final _boundary = find.byKey(const ValueKey('unread-message-boundary'));

/// Presses and lets go of the right button over the message at [index].
Future<void> _rightClick(
  WidgetTester tester,
  SessionHarness session,
  int index,
) async {
  final mouse = await tester.startGesture(
    tester.getCenter(session.messageRow(_idOf(index))),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.up();
  await session.settle();
}

void _routeHistory(FakeDiscordTransport transport) => transport.on(
  'GET',
  ChannelHistoryFixture.messagesPath,
  (_) => jsonResponse(ChannelHistoryFixture.page(10, 6)),
);

/// READY for an account that has read all of messages 10 to 15.
Map<String, Object?> _readyAllRead() =>
    ChannelHistoryFixture.readyWithUnread(firstUnread: 16, newest: 15);

Future<void> _markUnreadFrom(
  WidgetTester tester,
  SessionHarness session,
  int index,
) async {
  await _rightClick(tester, session, index);
  await tester.tap(_markUnread);
  await session.settle();
}

/// Whether the NEW line is drawn between the message at [index] and the one
/// before it.
void _expectBoundaryAbove(
  WidgetTester tester,
  SessionHarness session,
  int index,
) {
  final line = tester.getTopLeft(_boundary).dy;
  expect(
    tester.getTopLeft(session.messageRow(_idOf(index))).dy,
    greaterThan(line),
  );
  expect(
    tester.getBottomLeft(session.messageRow(_idOf(index - 1))).dy,
    lessThanOrEqualTo(line),
  );
}

void main() {
  group('Mark unread', () {
    testSession(
      'puts the NEW line above the message and tells Discord',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        expect(_boundary, findsNothing);

        await _markUnreadFrom(tester, session, 12);

        _expectBoundaryAbove(tester, session, 12);
        final ack = session.transport.requests.singleWhere(
          (request) =>
              request.method == 'POST' &&
              request.uri.path ==
                  '${ChannelHistoryFixture.messagesPath}/${_idOf(11)}/ack',
        );
        expect(ack.json, {'manual': true, 'mention_count': 0});
      },
      ready: _readyAllRead(),
      routes: _routeHistory,
      platform: TargetPlatform.windows,
    );

    testSession(
      'moves the NEW line when used again',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await _markUnreadFrom(tester, session, 14);
        _expectBoundaryAbove(tester, session, 14);

        await _markUnreadFrom(tester, session, 12);
        _expectBoundaryAbove(tester, session, 12);

        await _markUnreadFrom(tester, session, 13);
        _expectBoundaryAbove(tester, session, 13);
      },
      ready: _readyAllRead(),
      routes: _routeHistory,
      platform: TargetPlatform.windows,
    );
  });

  final reactionPath =
      '${ChannelHistoryFixture.messagesPath}/${_idOf(12)}'
      '/reactions/${Uri.encodeComponent('🚀')}/@me';

  testSession(
    'Add reaction opens the picker and reacts with the choice',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _rightClick(tester, session, 12);

      await tester.tap(_addReaction);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('emoji-search')),
        'rocket',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('emoji-choice-unicode-rocket')),
      );
      await session.settle();

      expect(find.byKey(const ValueKey('emoji-picker')), findsNothing);
      expect(
        session.transport.requests.where(
          (request) =>
              request.method == 'PUT' && request.uri.path == reactionPath,
        ),
        hasLength(1),
      );
    },
    routes: (transport) {
      _routeHistory(transport);
      transport.on(
        'PUT',
        reactionPath,
        (_) => jsonResponse(null, statusCode: 204),
      );
    },
    platform: TargetPlatform.windows,
  );
}
