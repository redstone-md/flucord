import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';

final _profileCard = find.byKey(const ValueKey('member-profile-popover'));

Future<void> _openWithMessageFromFriend(SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
      id: _messageId,
      channelId: SessionHarness.channelId,
      guildId: SessionHarness.guildId,
      authorId: SessionHarness.friendId,
      content: 'hello',
    ),
  );
}

void main() {
  group('clicking an author', () {
    testSession('on the name opens their profile', (tester, session) async {
      await _openWithMessageFromFriend(session);

      await tester.tap(
        find.descendant(
          of: session.messageRow(_messageId),
          matching: find.byKey(const ValueKey('message-author-name')),
        ),
      );
      await session.settle();

      expect(_profileCard, findsOneWidget);
    });

    testSession('on the avatar opens their profile', (tester, session) async {
      await _openWithMessageFromFriend(session);

      await tester.tap(
        find.descendant(
          of: session.messageRow(_messageId),
          matching: find.byKey(const ValueKey('message-author-avatar')),
        ),
      );
      await session.settle();

      expect(_profileCard, findsOneWidget);
    });
  });
}
