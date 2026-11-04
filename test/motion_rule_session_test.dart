import 'package:flucord/src/domain/accessibility.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_harness.dart';

/// READY where the friend wears an animated avatar.
Map<String, Object?> _animatedFriend() =>
    SessionHarness.defaultReady()
      ..['users'] = [
        {
          'id': SessionHarness.friendId,
          'username': 'friend',
          'global_name': 'Friend',
          'avatar': 'a_0123456789abcdef',
        },
      ];

final _dmRow = find.byKey(
  const ValueKey('channel-${SessionHarness.dmChannelId}'),
);

/// The address the friend's avatar in the DM list asks for now.
String _avatarUrl(WidgetTester tester) {
  final image = tester.widget<Image>(
    find.descendant(
      of: _dmRow,
      matching: find.byKey(
        const ValueKey('member-avatar-image-${SessionHarness.friendId}'),
      ),
    ),
  );
  return (image.image as NetworkImage).url;
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

void main() {
  group('an animated avatar', () {
    testSession(
      'holds its still until the pointer is on its row, and draws no frames',
      (tester, session) async {
        await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
        await session.settle();

        expect(_avatarUrl(tester), contains('.webp'));
        // Once the switch to the DM list has finished, nothing ticks.
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isFalse);

        final mouse = await _mouse(tester);
        await mouse.moveTo(tester.getCenter(_dmRow));
        await tester.pump();
        expect(_avatarUrl(tester), contains('.gif'));

        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(_avatarUrl(tester), contains('.webp'));
      },
      ready: _animatedFriend(),
    );

    testSession(
      'stays still on hover under reduced motion',
      (tester, session) async {
        await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
        await session.settle();

        final mouse = await _mouse(tester);
        await mouse.moveTo(tester.getCenter(_dmRow));
        await tester.pump();

        expect(_avatarUrl(tester), contains('.webp'));
      },
      ready: _animatedFriend(),
      accessibility: const AccessibilitySettings(reducedMotion: true),
    );

    testSession(
      'stays still on hover while the window is unfocused',
      (tester, session) async {
        await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
        await session.settle();
        session.blurWindow();
        await session.settle();

        final mouse = await _mouse(tester);
        await mouse.moveTo(tester.getCenter(_dmRow));
        await tester.pump();

        expect(_avatarUrl(tester), contains('.webp'));
      },
      ready: _animatedFriend(),
    );
  });
}
