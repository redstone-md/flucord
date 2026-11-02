import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';
import 'support/type_scale.dart';

/// Text in a real session comes in the sizes of the type scale, none under
/// 12 px: the timeline, the sidebars and the dialogs people open most.
void main() {
  Map<String, Object?> fromFriend(String id, String content, String time) =>
      rawMessage(
        id: id,
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: SessionHarness.friendId,
        content: content,
        timestamp: '2026-07-25T$time:00+00:00',
      );

  testSession('the timeline and the sidebars', (tester, session) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch(
      'MESSAGE_CREATE',
      fromFriend('400000000000000001', 'Hello **there**, `code`', '10:00'),
    );
    await session.dispatch(
      'MESSAGE_CREATE',
      fromFriend('400000000000000002', 'A second line', '10:01')
        ..['edited_timestamp'] = '2026-07-25T10:02:00+00:00'
        ..['reactions'] = [
          {
            'count': 2,
            'me': false,
            'emoji': {'id': null, 'name': '👍'},
          },
        ],
    );
    await session.dispatch(
      'MESSAGE_CREATE',
      fromFriend('400000000000000003', 'A reply', '10:30')
        ..['type'] = 19
        ..['message_reference'] = {'message_id': '400000000000000001'}
        ..['referenced_message'] = fromFriend(
          '400000000000000001',
          'Hello there',
          '10:00',
        ),
    );

    expectTextOnTypeScale(tester, glyphs: {'👍'});
  });

  testSession('the user settings dialog', (tester, session) async {
    await tester.tap(find.byTooltip('User settings'));
    await session.settle();

    expectTextOnTypeScale(tester);
  });

  testSession('the connections dialog', (tester, session) async {
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await session.settle();

    expectTextOnTypeScale(tester);
  });

  testSession('the quick switcher', (tester, session) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await session.settle();

    expectTextOnTypeScale(tester);
  });
}
