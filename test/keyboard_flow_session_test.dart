import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/channel_history_fixture.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _friendMessage = '900000000000000001';

final _composer = find.byKey(const ValueKey('message-composer'));

/// Sends a message from a friend into the guild's first channel.
Future<void> _receive(
  SessionHarness session,
  String id, {
  String body = 'hello from a friend',
}) => session.dispatch(
  'MESSAGE_CREATE',
  rawMessage(
    id: id,
    channelId: SessionHarness.channelId,
    guildId: SessionHarness.guildId,
    authorId: SessionHarness.friendId,
    content: body,
  ),
);

const _idOf = ChannelHistoryFixture.idOf;
const _page = ChannelHistoryFixture.page;

/// The channel holds messages 0 to 99, all on one page.
const _newest = 99;

/// How long a plain ack waits before it goes out.
const _ackDebounce = Duration(seconds: 3);

final _jumpToPresent = find.byKey(const ValueKey('jump-to-present'));
final _newLine = find.byKey(const ValueKey('unread-message-boundary'));
final _replyBar = find.textContaining('Replying to');

void _routeHistory(FakeDiscordTransport transport) {
  transport.on('GET', ChannelHistoryFixture.messagesPath, (request) {
    final around = request.uri.queryParameters['around'];
    if (around == null) return jsonResponse(_page(0, _newest + 1));
    return jsonResponse(_page(ChannelHistoryFixture.indexOf(around) - 5, 10));
  });
}

Future<void> _scrollUp(WidgetTester tester, SessionHarness session) async {
  final list = find
      .ancestor(
        of: find.byType(MessageItem),
        matching: find.byType(CustomScrollView),
      )
      .first;
  await tester.drag(list, const Offset(0, 900));
  await session.settle();
}

/// The newest message whose row sits in the middle of the screen.
int _indexOnScreen(WidgetTester tester, SessionHarness session) {
  for (var index = _newest; index >= 0; index--) {
    final row = session.messageRow(_idOf(index));
    if (row.evaluate().isEmpty) continue;
    final top = tester.getTopLeft(row).dy;
    if (top > 200 && top < 500) return index;
  }
  throw StateError('No message row is on screen.');
}

/// Starts a reply from the message menu of [index], as the mouse does.
Future<void> _startReply(
  WidgetTester tester,
  SessionHarness session,
  int index,
) async {
  final mouse = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.down(tester.getCenter(session.messageRow(_idOf(index))));
  await tester.pump();
  await mouse.up();
  await tester.pump();
  await mouse.removePointer();
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('message-menu-reply')));
  await tester.pumpAndSettle();
}

Future<void> _pressEscape(WidgetTester tester, SessionHarness session) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await session.settle();
}

/// Every message acked so far, after the wait a plain ack takes.
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

String _boxText(WidgetTester tester) =>
    tester.widget<TextField>(_composer).controller!.text;

/// Types as the keyboard does when a text field has the focus. With no field
/// focused, the test input has no client and this throws.
Future<void> _typeInFocusedField(WidgetTester tester, String text) async {
  tester.testTextInput.enterText(text);
  await tester.pump();
}

/// Presses a key that makes a character, with no text field in between.
Future<void> _pressCharacter(
  WidgetTester tester,
  LogicalKeyboardKey key,
  String character,
) async {
  await tester.sendKeyEvent(key, character: character);
  await tester.pump();
}

/// Holds [modifiers] and presses [key], as a person does.
Future<void> _chord(
  WidgetTester tester,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

/// Clicks a row of the timeline, which takes the focus from the composer on a
/// desktop platform.
Future<void> _clickRow(
  WidgetTester tester,
  SessionHarness session,
  String id,
) async {
  await tester.tapAt(tester.getCenter(session.messageRow(id)));
  await session.settle();
}

/// Clicks where nothing can take the focus, which leaves it with no widget.
Future<void> _clickEmptySpace(
  WidgetTester tester,
  SessionHarness session,
) async {
  await tester.tapAt(
    tester.getBottomLeft(find.byKey(const ValueKey('channel-sidebar'))) +
        const Offset(100, -120),
  );
  await session.settle();
}

Future<void> _quickSwitch(
  WidgetTester tester,
  SessionHarness session,
  String name,
) async {
  await _chord(tester, const [
    LogicalKeyboardKey.controlLeft,
  ], LogicalKeyboardKey.keyK);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('quick-switcher-search')),
    name,
  );
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  await session.settle();
}

void main() {
  group('typing goes to the composer', () {
    testSession(
      'after a click on another channel',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await tester.tap(
          find.byKey(
            const ValueKey('channel-${SessionHarness.otherChannelId}'),
          ),
        );
        await session.settle();
        await _typeInFocusedField(tester, 'hello');

        expect(_boxText(tester), 'hello');
      },
    );

    testSession('after a quick switch to another channel', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);

      await _quickSwitch(tester, session, 'random');
      await _typeInFocusedField(tester, 'hello');

      expect(_boxText(tester), 'hello');
      expect(find.widgetWithText(TextField, 'hello'), findsOneWidget);
    });

    testSession(
      'after a quick switch to the channel already open',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _receive(session, _friendMessage);
        await _clickRow(tester, session, _friendMessage);

        await _quickSwitch(tester, session, 'general');
        await _typeInFocusedField(tester, 'hello');

        expect(_boxText(tester), 'hello');
      },
    );

    testSession(
      'when a printable key is pressed with the focus elsewhere',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _receive(session, _friendMessage);
        await _clickRow(tester, session, _friendMessage);

        await _pressCharacter(tester, LogicalKeyboardKey.keyH, 'h');

        expect(_boxText(tester), 'h');
        // The rest of the word arrives through the box's own text input.
        await _typeInFocusedField(tester, 'hi');
        expect(_boxText(tester), 'hi');
      },
    );

    testSession(
      'with the keystroke that opens suggestions still opening them',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _receive(session, _friendMessage);
        await _clickRow(tester, session, _friendMessage);

        await _pressCharacter(tester, LogicalKeyboardKey.digit3, '#');
        await session.settle();

        expect(_boxText(tester), '#');
        expect(
          find.byKey(const ValueKey('composer-autocomplete')),
          findsOneWidget,
        );
      },
    );

    testSession(
      'but not a key held with Ctrl',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _receive(session, _friendMessage);
        await _clickRow(tester, session, _friendMessage);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await _pressCharacter(tester, LogicalKeyboardKey.keyB, 'b');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        expect(_boxText(tester), isEmpty);
      },
    );

    testSession('but not while another text field has the focus', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await tester.tap(find.byKey(const ValueKey('message-search')));
      await tester.pump();

      await _pressCharacter(tester, LogicalKeyboardKey.keyH, 'h');

      expect(_boxText(tester), isEmpty);
    });

    testSession('but not while a dialog is open', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _chord(tester, const [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();

      await _pressCharacter(tester, LogicalKeyboardKey.keyH, 'h');

      expect(_boxText(tester), isEmpty);
    });
  });

  testSession(
    'Ctrl+K still works after a click on empty space',
    platform: TargetPlatform.windows,
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _clickEmptySpace(tester, session);

      await _chord(tester, const [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick-switcher')), findsOneWidget);
    },
  );

  group('Esc', () {
    testSession(
      'cancels a reply first, then the next press scrolls to the end',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _scrollUp(tester, session);
        expect(_jumpToPresent, findsOneWidget);
        final index = _indexOnScreen(tester, session);
        final onScreen = session.messageRow(_idOf(index));
        await _startReply(tester, session, index);
        expect(_replyBar, findsOneWidget);

        await _pressEscape(tester, session);

        expect(_replyBar, findsNothing);
        expect(_jumpToPresent, findsOneWidget);
        expect(onScreen, findsOneWidget);

        await _pressEscape(tester, session);

        expect(_jumpToPresent, findsNothing);
        expect(session.messageRow(_idOf(_newest)), findsOneWidget);
      },
      routes: _routeHistory,
    );

    testSession(
      'marks the channel read: the NEW line goes and the ack goes out',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await tester.pumpAndSettle();
        expect(_newLine, findsOneWidget);

        await _pressEscape(tester, session);

        expect(_newLine, findsNothing);
        expect(await _ackedMessages(tester, session), [_idOf(_newest)]);
      },
      routes: _routeHistory,
      ready: ChannelHistoryFixture.readyWithUnread(
        firstUnread: _newest - 4,
        newest: _newest,
      ),
    );

    testSession(
      'works with the focus out of the composer',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _scrollUp(tester, session);
        await _clickEmptySpace(tester, session);

        await _pressEscape(tester, session);

        expect(_jumpToPresent, findsNothing);
      },
      routes: _routeHistory,
    );

    testSession(
      'closes open suggestions and goes no further',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _startReply(tester, session, _newest);
        await tester.enterText(_composer, '#');
        await session.settle();
        expect(
          find.byKey(const ValueKey('composer-autocomplete')),
          findsOneWidget,
        );

        await _pressEscape(tester, session);

        expect(
          find.byKey(const ValueKey('composer-autocomplete')),
          findsNothing,
        );
        expect(_replyBar, findsOneWidget);
        expect(_boxText(tester), '#');
      },
      routes: _routeHistory,
    );

    testSession(
      'closes a dialog and leaves the reply alone',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _startReply(tester, session, _newest);
        await _chord(tester, const [
          LogicalKeyboardKey.controlLeft,
        ], LogicalKeyboardKey.keyK);
        await tester.pumpAndSettle();

        await _pressEscape(tester, session);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('quick-switcher')), findsNothing);
        expect(_replyBar, findsOneWidget);
      },
      routes: _routeHistory,
    );
  });
}
