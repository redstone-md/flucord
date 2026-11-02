import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';

/// What a screen reader gets for the widget with this key.
SemanticsNode _announced(WidgetTester tester, String key) =>
    tester.getSemantics(find.byKey(ValueKey(key)));

/// A message in a channel the reader is not looking at.
Map<String, Object?> _elsewhere(String id, {bool mentionsMe = false}) => {
  ...rawMessage(
    id: id,
    channelId: SessionHarness.otherChannelId,
    guildId: SessionHarness.guildId,
    authorId: SessionHarness.friendId,
    content: 'hello',
  ),
  if (mentionsMe)
    'mentions': [
      {'id': SessionHarness.currentUserId, 'username': 'me'},
    ],
};

void main() {
  group('a channel row', () {
    testSession('announces that it is selected', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      expect(
        _announced(tester, 'channel-${SessionHarness.channelId}'),
        containsSemantics(
          label: 'general',
          isButton: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      expect(
        _announced(tester, 'channel-${SessionHarness.otherChannelId}'),
        containsSemantics(label: 'random', isSelected: false),
      );
    });

    testSession('announces unread messages', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch('MESSAGE_CREATE', _elsewhere(_messageId));

      expect(
        _announced(tester, 'channel-${SessionHarness.otherChannelId}'),
        containsSemantics(label: 'random, unread'),
      );
    });

    testSession('announces how many mentions wait', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch(
        'MESSAGE_CREATE',
        _elsewhere(_messageId, mentionsMe: true),
      );
      expect(
        _announced(tester, 'channel-${SessionHarness.otherChannelId}'),
        containsSemantics(label: 'random, 1 mention'),
      );

      await session.dispatch(
        'MESSAGE_CREATE',
        _elsewhere('900000000000000002', mentionsMe: true),
      );
      expect(
        _announced(tester, 'channel-${SessionHarness.otherChannelId}'),
        containsSemantics(label: 'random, 2 mentions'),
      );
    });
  });
}
