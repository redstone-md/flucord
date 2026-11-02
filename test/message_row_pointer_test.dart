import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
