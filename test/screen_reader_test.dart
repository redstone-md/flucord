import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';
const _categoryId = '800000000000000001';

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

/// The default account, with its channels under one category.
Map<String, Object?> _readyWithCategory() => {
  ...SessionHarness.defaultReady(),
  'guilds': [
    rawGuild(
      id: SessionHarness.guildId,
      name: 'The Forge',
      channels: [
        {...rawChannel(id: _categoryId, name: 'Text channels'), 'type': 4},
        {
          ...rawChannel(id: SessionHarness.channelId, name: 'general'),
          'parent_id': _categoryId,
        },
      ],
    ),
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

  testSession('a category announces whether it is expanded', (
    tester,
    session,
  ) async {
    await tester.tap(
      find.byKey(const ValueKey('space-${SessionHarness.guildId}')),
    );
    await session.settle();

    expect(
      _announced(tester, 'category-$_categoryId'),
      containsSemantics(
        label: 'Text channels',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('category-$_categoryId')));
    await session.settle();

    expect(
      _announced(tester, 'category-$_categoryId'),
      containsSemantics(hasExpandedState: true, isExpanded: false),
    );
  }, ready: _readyWithCategory());
}
