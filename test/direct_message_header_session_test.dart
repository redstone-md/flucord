import 'package:flucord/src/presentation/widgets/chat_header.dart';
import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_font.dart';
import 'support/session_harness.dart';

// The DM header in direction B (FLUCORD-82): the person's avatar with a
// status dot, then their whole name, at the window size the app opens with.

const _name = 'Konstantin Konstantinopolsky';

Map<String, Object?> _ready() {
  final ready = SessionHarness.defaultReady();
  ready['users'] = [
    {
      'id': SessionHarness.friendId,
      'username': 'konstantin',
      'global_name': _name,
    },
  ];
  return ready;
}

void main() {
  testSession(
    'a DM header shows the avatar and the whole name',
    (tester, session) async {
      await loadAppFont(tester);
      await session.openChannel(
        SessionHarness.dmChannelId,
        space: 'direct-messages',
      );

      final header = find.byType(ChatHeader);
      final avatar = find.descendant(
        of: header,
        matching: find.byType(MemberAvatar),
      );
      expect(tester.getSize(avatar), const Size.square(24));
      expect(
        find.descendant(
          of: avatar,
          matching: find.byKey(
            const ValueKey('member-presence-${SessionHarness.friendId}'),
          ),
        ),
        findsOneWidget,
      );

      final title = find.descendant(of: header, matching: find.text(_name));
      expect(tester.getRect(avatar).right, lessThan(tester.getRect(title).left));
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
        reason: 'the whole name is drawn, not cut with an ellipsis',
      );
    },
    ready: _ready(),
    // The window the app opens with on Linux.
    size: const Size(1280, 720),
  );
}
