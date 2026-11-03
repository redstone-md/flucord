import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/presentation/conversation_pane.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';

import 'support/session_harness.dart';

/// The shell draws chat and the member list in one card, the canvas. The
/// rail and the channel sidebar stay outside it, on the darkest background.
void main() {
  const window = Size(1440, 900);
  final card = find.byKey(const ValueKey('canvas-card'));
  final rail = find.byKey(const ValueKey('server-rail'));
  final sidebar = find.byKey(const ValueKey('channel-sidebar'));

  Finder inCard(Finder finder) => find.descendant(of: card, matching: finder);

  testSession('chat and the member list sit in the card, navigation does not', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);

    expect(inCard(find.byType(ConversationPane)), findsOneWidget);
    expect(inCard(find.byType(MemberSidebar)), findsOneWidget);
    expect(inCard(rail), findsNothing);
    expect(inCard(sidebar), findsNothing);

    // 8 px in from the window on the top, right and bottom, and flush
    // against the channel sidebar on the left.
    final cardRect = tester.getRect(card);
    expect(cardRect.top, 8);
    expect(cardRect.right, window.width - 8);
    expect(cardRect.bottom, window.height - 8);
    expect(cardRect.left, tester.getRect(sidebar).right);
  }, size: window);
}
