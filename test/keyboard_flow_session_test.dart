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

/// A channel of 100 messages from a friend, except those in [mine], which this
/// account wrote. [extra] changes the raw message of an index.
void Function(FakeDiscordTransport) _historyWithOwn(
  Set<int> mine, {
  Map<int, Map<String, Object?>> extra = const {},
}) =>
    (transport) => transport.on(
      'GET',
      ChannelHistoryFixture.messagesPath,
      (_) => jsonResponse([
        for (var index = _newest; index >= 0; index--)
          {
            ...ChannelHistoryFixture.message(
              index,
              authorId: mine.contains(index)
                  ? SessionHarness.currentUserId
                  : SessionHarness.friendId,
            ),
            ...?extra[index],
          },
      ]),
    );

Finder _editField(int index) => find.byKey(ValueKey('edit-${_idOf(index)}'));

/// Answers an edit of the message at [index], and returns the edits sent.
List<Object?> _acceptEdits(SessionHarness session, int index) {
  final path = '${ChannelHistoryFixture.messagesPath}/${_idOf(index)}';
  final sent = <Object?>[];
  session.transport.on('PATCH', path, (request) {
    final body = request.json as Map<String, Object?>;
    sent.add(body['content']);
    return jsonResponse({
      ...ChannelHistoryFixture.message(
        index,
        authorId: SessionHarness.currentUserId,
        content: body['content']! as String,
      ),
      'edited_timestamp': '2026-07-21T00:00:00Z',
    });
  });
  return sent;
}

Future<void> _pressUp(WidgetTester tester, SessionHarness session) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
  await session.settle();
}

const _third = '300000000000000004';
const _fourth = '300000000000000005';
const _category = '300000000000000006';
const _voice = '300000000000000007';

const _alt = LogicalKeyboardKey.altLeft;
const _shift = LogicalKeyboardKey.shiftLeft;
const _control = LogicalKeyboardKey.controlLeft;
const _command = LogicalKeyboardKey.metaLeft;
const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;

/// The default READY with other channels, and with read state [entries].
Map<String, Object?> _readyWith(
  List<Object?> channels, {
  List<Object?> entries = const [],
}) {
  final ready = SessionHarness.defaultReady();
  final guild = (ready['guilds']! as List).single as Map<String, Object?>;
  return ready
    ..['guilds'] = [
      {...guild, 'channels': channels},
    ]
    ..['read_state'] = {'version': 1, 'partial': false, 'entries': entries};
}

Map<String, Object?> _channel(String id, String name, {int position = 0}) => {
  ...rawChannel(id: id, name: name),
  'position': position,
};

/// A channel with a newer message than the read state's cursor [_unreadEntry].
Map<String, Object?> _unreadChannel(String id, String name) =>
    rawChannel(id: id, name: name, lastMessageId: _idOf(5));

Map<String, Object?> _unreadEntry(String id, {int mentions = 0}) => {
  'id': id,
  'last_message_id': _idOf(1),
  'mention_count': mentions,
};

/// The channel on screen, as the composer's hint names it.
void _expectOpen(String channelName) =>
    expect(find.text('Message #$channelName'), findsOneWidget);

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

  group('Up on an empty box', () {
    const own = _newest - 3;

    testSession(
      'opens the last own message, and the edit gives the focus back',
      (tester, session) async {
        final edits = _acceptEdits(session, own);
        await session.openChannel(SessionHarness.channelId);

        await _pressUp(tester, session);
        expect(_editField(own), findsOneWidget);

        await _typeInFocusedField(tester, 'changed');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await session.settle();

        expect(edits, ['changed']);
        expect(_editField(own), findsNothing);
        await _typeInFocusedField(tester, 'next');
        expect(_boxText(tester), 'next');
      },
      routes: _historyWithOwn({own - 10, own}),
    );

    testSession(
      'gives the focus back when Esc cancels the edit',
      (tester, session) async {
        final edits = _acceptEdits(session, own);
        await session.openChannel(SessionHarness.channelId);
        await _pressUp(tester, session);
        expect(_editField(own), findsOneWidget);

        await _typeInFocusedField(tester, 'changed');
        await _pressEscape(tester, session);

        expect(edits, isEmpty);
        expect(_editField(own), findsNothing);
        await _typeInFocusedField(tester, 'next');
        expect(_boxText(tester), 'next');
      },
      routes: _historyWithOwn({own}),
    );

    testSession(
      'an edit of the newest message stays in view, and a key keeps it there',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(session.messageRow(_idOf(_newest))),
        );
        addTearDown(mouse.removePointer);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit'));
        await tester.pumpAndSettle();

        void expectInView() {
          final field = tester.getRect(_editField(_newest));
          expect(
            field.bottom,
            lessThanOrEqualTo(tester.getTopLeft(_composer).dy),
          );
          expect(_jumpToPresent, findsNothing);
        }

        expectInView();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expectInView();
      },
      routes: _historyWithOwn({_newest}),
    );

    testSession('saves on Numpad Enter too', (tester, session) async {
      final edits = _acceptEdits(session, own);
      await session.openChannel(SessionHarness.channelId);
      await _pressUp(tester, session);

      await _typeInFocusedField(tester, 'changed');
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await session.settle();

      expect(edits, ['changed']);
    }, routes: _historyWithOwn({own}));

    // The first is too far up to be built. The second is built, but off screen.
    for (final index in [5, _newest - 15]) {
      testSession(
        'brings the message at $index of 100 into view',
        (tester, session) async {
          await session.openChannel(SessionHarness.channelId);

          await _pressUp(tester, session);
          await tester.pumpAndSettle();

          expect(_editField(index), findsOneWidget);
          final top = tester.getTopLeft(_editField(index)).dy;
          expect(top, inInclusiveRange(0, tester.getTopLeft(_composer).dy));
        },
        routes: _historyWithOwn({index}),
      );
    }

    testSession(
      'passes over what cannot be edited',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await _pressUp(tester, session);

        expect(_editField(own), findsOneWidget);
      },
      routes: _historyWithOwn(
        {own, own + 1, own + 2},
        extra: {
          // A voice message, and the notice that this account pinned something.
          own + 1: {'flags': 8192},
          own + 2: {'type': 6},
        },
      ),
    );

    testSession('does nothing with text in the box', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await tester.enterText(_composer, 'words');
      await session.settle();

      await _pressUp(tester, session);

      expect(_editField(own), findsNothing);
    }, routes: _historyWithOwn({own}));

    testSession(
      'leaves the box alone when the account has written nothing here',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await _pressUp(tester, session);
        await _typeInFocusedField(tester, 'still here');

        expect(_boxText(tester), 'still here');
      },
      routes: _historyWithOwn(const {}),
    );
  });

  group('navigation shortcuts', () {
    testSession('Alt+Up and Alt+Down walk the channels and wrap around', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);

      await _chord(tester, const [_alt], _down);
      await session.settle();
      _expectOpen('random');
      await _typeInFocusedField(tester, 'hello');
      expect(_boxText(tester), 'hello');

      await _chord(tester, const [_alt], _down);
      await session.settle();
      _expectOpen('general');

      await _chord(tester, const [_alt], _up);
      await session.settle();
      _expectOpen('random');
    });

    testSession(
      'Alt+Down walks in the order of the sidebar and passes voice channels',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await _chord(tester, const [_alt], _down);
        await session.settle();
        _expectOpen('in-category-first');

        await _chord(tester, const [_alt], _down);
        await session.settle();
        _expectOpen('in-category-last');

        await _chord(tester, const [_alt], _down);
        await session.settle();
        _expectOpen('general');
      },
      ready: _readyWith([
        {
          'id': _category,
          'type': 4,
          'name': 'Rooms',
          'position': 0,
          'permission_overwrites': <Object?>[],
        },
        _channel(SessionHarness.channelId, 'general'),
        {
          ..._channel(_third, 'in-category-last', position: 2),
          'parent_id': _category,
        },
        {
          ..._channel(_fourth, 'in-category-first', position: 1),
          'parent_id': _category,
        },
        {..._channel(_voice, 'lounge'), 'type': 2, 'parent_id': _category},
      ]),
    );

    testSession(
      'Alt+Shift+Down goes to the next unread channel',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await _chord(tester, const [_alt, _shift], _down);
        await session.settle();

        _expectOpen('loud');
      },
      ready: _readyWith(
        [
          _channel(SessionHarness.channelId, 'general'),
          _channel(SessionHarness.otherChannelId, 'quiet', position: 1),
          {..._unreadChannel(_third, 'loud'), 'position': 2},
        ],
        entries: [_unreadEntry(_third)],
      ),
    );

    testSession(
      'Ctrl+Alt+Shift+Down goes to the next channel with a mention',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await _chord(tester, const [_control, _alt, _shift], _down);
        await session.settle();

        _expectOpen('pinged');
      },
      ready: _readyWith(
        [
          _channel(SessionHarness.channelId, 'general'),
          {..._unreadChannel(_third, 'loud'), 'position': 1},
          {..._unreadChannel(_fourth, 'pinged'), 'position': 2},
        ],
        entries: [_unreadEntry(_third), _unreadEntry(_fourth, mentions: 1)],
      ),
    );

    testSession('Ctrl+Alt+Up and Down walk the servers', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);

      await _chord(tester, const [_control, _alt], _up);
      await session.settle();
      expect(find.text('Message #general'), findsNothing);

      await _chord(tester, const [_control, _alt], _down);
      await session.settle();
      _expectOpen('general');
    });

    testSession('Alt+Left and Alt+Right walk the history of channels', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await _chord(tester, const [_alt], _down);
      await session.settle();
      _expectOpen('random');

      await _chord(tester, const [_alt], LogicalKeyboardKey.arrowLeft);
      await session.settle();
      _expectOpen('general');

      await _chord(tester, const [_alt], LogicalKeyboardKey.arrowRight);
      await session.settle();
      _expectOpen('random');
    });

    testSession(
      'Page Up and Page Down scroll the timeline with the focus in the box',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        expect(_jumpToPresent, findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await session.settle();
        expect(_jumpToPresent, findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await session.settle();
        expect(_jumpToPresent, findsNothing);
      },
      routes: _routeHistory,
    );

    group('on macOS', () {
      testSession(
        'Cmd takes the place of Ctrl',
        platform: TargetPlatform.macOS,
        (tester, session) async {
          await session.openChannel(SessionHarness.channelId);

          await _chord(tester, const [_control], LogicalKeyboardKey.keyK);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('quick-switcher')), findsNothing);

          await _chord(tester, const [_command], LogicalKeyboardKey.keyK);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('quick-switcher')), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();

          await _chord(tester, const [_command, _alt], _up);
          await session.settle();
          expect(find.text('Message #general'), findsNothing);
          await _chord(tester, const [_command, _alt], _down);
          await session.settle();
          _expectOpen('general');
        },
      );

      testSession(
        'Option walks the channels, and Cmd with a bracket walks the history',
        platform: TargetPlatform.macOS,
        (tester, session) async {
          await session.openChannel(SessionHarness.channelId);

          await _chord(tester, const [_alt], _down);
          await session.settle();
          _expectOpen('random');

          await _chord(tester, const [
            _command,
          ], LogicalKeyboardKey.bracketLeft);
          await session.settle();
          _expectOpen('general');

          await _chord(tester, const [
            _command,
          ], LogicalKeyboardKey.bracketRight);
          await session.settle();
          _expectOpen('random');
        },
      );
    });
  });

  group('the reaction picker', () {
    /// Opens the picker of the newest message with the mouse. The focus is in
    /// the composer until then.
    Future<void> openPicker(WidgetTester tester, SessionHarness session) async {
      final row = session.messageRow(_idOf(_newest));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(row));
      addTearDown(mouse.removePointer);
      await tester.pump();
      final button = tester.getCenter(
        find.byKey(ValueKey('add-reaction-${_idOf(_newest)}')),
      );
      await mouse.moveTo(button);
      await tester.pump();
      await mouse.down(button);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close reaction picker'), findsOneWidget);
    }

    testSession(
      'takes the typing from the composer',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await openPicker(tester, session);

        await _typeInFocusedField(tester, 'smile');

        expect(_boxText(tester), isEmpty);
      },
      routes: _routeHistory,
    );

    testSession(
      'closes on Esc, and the reply stays',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await _startReply(tester, session, _newest);
        await openPicker(tester, session);

        await _pressEscape(tester, session);
        await tester.pumpAndSettle();

        expect(find.byTooltip('Close reaction picker'), findsNothing);
        expect(_replyBar, findsOneWidget);
      },
      routes: _routeHistory,
    );
  });
}
