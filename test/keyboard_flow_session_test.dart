import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
