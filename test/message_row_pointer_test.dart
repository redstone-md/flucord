import 'package:flucord/src/presentation/widgets/chat_header.dart';
import 'package:flucord/src/presentation/widgets/message_action_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/channel_history_fixture.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _upperId = '900000000000000001';
const _lowerId = '900000000000000002';
const _lowerBody = 'the lower message says something';

final _copyText = find.byKey(const ValueKey('message-menu-copy-text'));
final _copySelection = find.byKey(
  const ValueKey('message-menu-copy-selection'),
);
final _reply = find.byKey(const ValueKey('message-menu-reply'));
final _addReactionToLower = find.byKey(ValueKey('add-reaction-$_lowerId'));
final _addReactionToUpper = find.byKey(ValueKey('add-reaction-$_upperId'));

/// The text of a message as it is drawn, not as the row holds it.
Finder _drawn(String text) => find.textContaining(text, findRichText: true);

/// Opens the channel on two short rows from one author, one above the other.
Future<void> _openTwoRows(SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  for (final (id, body) in [(_upperId, 'above'), (_lowerId, _lowerBody)]) {
    await session.dispatch(
      'MESSAGE_CREATE',
      rawMessage(
        id: id,
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: SessionHarness.friendId,
        content: body,
      ),
    );
  }
}

/// The friend as an author, their name glowing in neon.
const _neonFriend = {
  'id': SessionHarness.friendId,
  'username': 'friend',
  'global_name': 'Neon',
  'display_name_styles': {
    'colors': [0xff5555],
    'font_id': 11,
    'effect_id': 3,
  },
};

/// Somebody else, so the second message starts its own group.
const _otherAuthor = {
  'id': '100000000000000077',
  'username': 'other',
  'global_name': 'Other',
};

/// More emoji in the server than the picker's grid shows at once.
Map<String, Object?> _readyWithManyEmoji() {
  final ready = SessionHarness.defaultReady();
  final guild = (ready['guilds']! as List).single as Map<String, Object?>;
  return ready
    ..['guilds'] = [
      {
        ...guild,
        'emojis': [
          for (var index = 0; index < 80; index++)
            {'id': '${400000000000000100 + index}', 'name': 'emoji_$index'},
        ],
      },
    ];
}

/// Everything the app puts on the clipboard from now on.
List<String> _watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

/// Presses the right button at [position] and holds it for [hold].
Future<void> _rightClick(
  WidgetTester tester,
  Offset position, {
  Duration hold = Duration.zero,
}) async {
  final mouse = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.down(position);
  await tester.pump(hold);
  await mouse.up();
  await tester.pump();
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

/// Drags the left button over the first part of [text].
Future<void> _selectStartOf(WidgetTester tester, Finder text) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  final start = tester.getTopLeft(text) + const Offset(1, 8);
  await mouse.down(start);
  await tester.pump();
  await mouse.moveTo(start + const Offset(60, 0));
  await tester.pump();
  await mouse.up();
  await tester.pump();
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

/// Rests a mouse on [position], with no button down.
Future<TestGesture> _hover(WidgetTester tester, Offset position) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: position);
  addTearDown(mouse.removePointer);
  await tester.pump();
  return mouse;
}

/// Taps [position] with the mouse that already rests there.
Future<void> _click(
  WidgetTester tester,
  TestGesture mouse,
  Offset position,
) async {
  await mouse.moveTo(position);
  await tester.pump();
  await mouse.down(position);
  await tester.pump();
  await mouse.up();
  await tester.pumpAndSettle();
}

void main() {
  group('the right button on message text', () {
    testSession(
      'opens the message menu, not the selection menu',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await _openTwoRows(session);

        await _rightClick(tester, tester.getCenter(_drawn(_lowerBody)));

        expect(_reply, findsOneWidget);
        expect(_copyText, findsOneWidget);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      },
    );

    testSession(
      'opens one menu when the button is held down',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await _openTwoRows(session);

        await _rightClick(
          tester,
          tester.getCenter(_drawn(_lowerBody)),
          hold: const Duration(milliseconds: 250),
        );

        expect(_copyText, findsOneWidget);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      },
    );

    testSession(
      'opens the message menu from text in an embed',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await session.dispatch('MESSAGE_CREATE', {
          ...rawMessage(
            id: _lowerId,
            channelId: SessionHarness.channelId,
            guildId: SessionHarness.guildId,
            authorId: SessionHarness.friendId,
            content: '',
          ),
          'embeds': [
            {'type': 'rich', 'description': 'words in an embed'},
          ],
        });

        await _rightClick(
          tester,
          tester.getCenter(_drawn('words in an embed')),
        );

        expect(_copyText, findsOneWidget);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      },
    );

    testSession(
      'offers no Copy when no text is selected',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await _openTwoRows(session);

        await _rightClick(tester, tester.getCenter(_drawn(_lowerBody)));

        expect(_copySelection, findsNothing);
      },
    );

    testSession(
      'offers Copy for the selected text',
      platform: TargetPlatform.windows,
      (tester, session) async {
        final copied = _watchClipboard(tester);
        await _openTwoRows(session);
        final text = _drawn(_lowerBody);
        await _selectStartOf(tester, text);

        await _rightClick(
          tester,
          tester.getTopLeft(text) + const Offset(20, 8),
        );
        await tester.tap(_copySelection);
        await tester.pumpAndSettle();

        expect(copied, hasLength(1));
        expect(_lowerBody, startsWith(copied.single));
        expect(copied.single, isNot(_lowerBody));
      },
    );
  });

  testSession(
    'the left button still selects text for the keyboard to copy',
    platform: TargetPlatform.windows,
    (tester, session) async {
      final copied = _watchClipboard(tester);
      await _openTwoRows(session);

      await _selectStartOf(tester, _drawn(_lowerBody));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(copied, hasLength(1));
      expect(_lowerBody, startsWith(copied.single));
    },
  );

  testSession(
    'a drag runs across two messages and copies names and text in order',
    platform: TargetPlatform.windows,
    (tester, session) async {
      final copied = _watchClipboard(tester);
      await session.openChannel(SessionHarness.channelId);
      for (final (id, body, author) in [
        (_upperId, 'above', _neonFriend),
        (_lowerId, _lowerBody, _otherAuthor),
      ]) {
        await session.dispatch(
          'MESSAGE_CREATE',
          rawMessage(
            id: id,
            channelId: SessionHarness.channelId,
            guildId: SessionHarness.guildId,
            authorId: author['id']! as String,
            content: body,
          )..['author'] = author,
        );
      }
      final upperName = find.descendant(
        of: session.messageRow(_upperId),
        matching: find.byKey(const ValueKey('message-author-name')),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(tester.getTopLeft(upperName) + const Offset(1, 8));
      await tester.pump();
      await mouse.moveTo(
        tester.getBottomRight(_drawn(_lowerBody)) - const Offset(1, 4),
      );
      await tester.pump();
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final text = copied.single;
      expect('Neon'.allMatches(text), hasLength(1), reason: text);
      final order = [
        text.indexOf('Neon'),
        text.indexOf('above'),
        text.indexOf('Other'),
        text.indexOf(_lowerBody),
      ];
      expect(order, everyElement(greaterThanOrEqualTo(0)), reason: text);
      expect(order, orderedEquals([...order]..sort()), reason: text);
    },
  );

  group('the hover bar', () {
    // It reaches over the row above, so the tests below click and cross the
    // part that lies outside its own row.
    testSession('floats over the top edge of the message, at its right', (
      tester,
      session,
    ) async {
      await _openTwoRows(session);
      await _hover(tester, tester.getCenter(session.messageRow(_lowerId)));

      final surface = tester.getRect(
        find.byKey(const ValueKey('message-surface-$_lowerId')),
      );
      final bar = tester.getRect(find.byType(MessageActionBar));

      expect(bar.top, surface.top - 16);
      expect(bar.bottom, greaterThan(surface.top));
      expect(bar.right, surface.right - 16);
    });

    testSession('stays inside the message list over the topmost message', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      for (var index = 0; index < 30; index++) {
        await session.dispatch(
          'MESSAGE_CREATE',
          rawMessage(
            id: '${900000000000000100 + index}',
            channelId: SessionHarness.channelId,
            guildId: SessionHarness.guildId,
            authorId: index.isEven
                ? SessionHarness.friendId
                : SessionHarness.currentUserId,
            content: 'line $index',
          ),
        );
      }
      final header = tester.getRect(find.byType(ChatHeader));
      // The last row that starts above the list's top edge.
      final top =
          [
            for (var index = 0; index < 30; index++)
              session.messageRow('${900000000000000100 + index}'),
          ].lastWhere(
            (row) =>
                row.evaluate().isNotEmpty &&
                tester.getRect(row).top < header.bottom,
          );
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('messages-${SessionHarness.channelId}'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      // Puts the message's top edge on the list's top edge.
      scroll.jumpTo(scroll.pixels - (header.bottom - tester.getRect(top).top));
      await tester.pump();
      expect(tester.getRect(top).top, closeTo(header.bottom, 1));

      await _hover(tester, tester.getRect(top).center);

      final bar = tester.getRect(find.byType(MessageActionBar));
      expect(bar.top, greaterThanOrEqualTo(header.bottom));
    });

    testSession('answers a click on the top edge of a button', (
      tester,
      session,
    ) async {
      await _openTwoRows(session);
      final mouse = await _hover(
        tester,
        tester.getCenter(session.messageRow(_lowerId)),
      );
      final button = tester.getRect(_addReactionToLower);

      await _click(tester, mouse, button.topCenter + const Offset(0, 1));

      expect(find.byTooltip('Close reaction picker'), findsOneWidget);
    });

    testSession('answers a click on the bottom edge of a button', (
      tester,
      session,
    ) async {
      await _openTwoRows(session);
      final mouse = await _hover(
        tester,
        tester.getCenter(session.messageRow(_lowerId)),
      );
      final button = tester.getRect(_addReactionToLower);

      await _click(tester, mouse, button.bottomCenter - const Offset(0, 1));

      expect(find.byTooltip('Close reaction picker'), findsOneWidget);
    });

    // The picker's grid scrolls, and its metrics rise through the row to the
    // list. A list that took them for its own scrolled past its end, bounced
    // back, and the bounce closed the picker.
    testSession(
      'opens the picker in a channel too short to scroll',
      platform: TargetPlatform.windows,
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        final row = session.messageRow(ChannelHistoryFixture.idOf(1));
        final mouse = await _hover(tester, tester.getCenter(row));
        final top = tester.getTopLeft(row);
        final button = find.byKey(
          ValueKey('add-reaction-${ChannelHistoryFixture.idOf(1)}'),
        );

        await _click(tester, mouse, tester.getCenter(button));

        expect(find.byTooltip('Close reaction picker'), findsOneWidget);
        expect(tester.getTopLeft(row), top);
      },
      routes: (transport) => transport.on(
        'GET',
        ChannelHistoryFixture.messagesPath,
        (_) => jsonResponse(ChannelHistoryFixture.page(0, 2)),
      ),
      ready: _readyWithManyEmoji(),
    );

    testSession('stays on its row while the pointer crosses it', (
      tester,
      session,
    ) async {
      await _openTwoRows(session);
      final mouse = await _hover(
        tester,
        tester.getCenter(session.messageRow(_lowerId)),
      );
      final button = tester.getRect(_addReactionToLower);

      for (final x in [button.left + 1, button.right - 1]) {
        await mouse.moveTo(Offset(x, button.top + 1));
        await tester.pump();

        expect(_addReactionToLower, findsOneWidget);
        expect(_addReactionToUpper, findsNothing);
      }
    });
  });
}
