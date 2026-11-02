import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/accessibility.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

void main() {
  const window = Size(1440, 900);
  const zoomed = AccessibilitySettings(zoom: 1.4);

  group('zoom lays the interface out again', () {
    testSession(
      'at 1.4 the composer and every pane stay on screen',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        for (final pane in [
          find.byKey(const ValueKey('channel-sidebar')),
          find.byKey(const ValueKey('account-panel')),
          find.byType(MessageComposer),
        ]) {
          _expectInside(tester.getRect(pane), window);
        }
      },
      size: window,
      accessibility: zoomed,
    );

    testSession(
      'at 0.8 the interface reaches the window edge',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        final composer = tester.getRect(find.byType(MessageComposer));
        expect(composer.bottom, closeTo(window.height, 0.5));
        // The member list, 224 px wide, is drawn at 0.8 to its right.
        expect(composer.right, closeTo(window.width - 224 * 0.8, 0.5));
      },
      size: window,
      accessibility: const AccessibilitySettings(zoom: 0.8),
    );
  });

  group('dialogs and menus follow the dials', () {
    const dials = AccessibilitySettings(
      zoom: 1.4,
      fontScale: 1.25,
      reducedMotion: true,
    );

    testSession('moving the zoom dial lays the app out again at once', (
      tester,
      session,
    ) async {
      final before = tester.getSize(find.byType(Scaffold).first).width;

      await tester.tap(find.byKey(const ValueKey('open-user-settings')));
      await session.settle();
      final navigation = find.byKey(
        const ValueKey('settings-nav-accessibility'),
      );
      await tester.scrollUntilVisible(
        navigation,
        100,
        scrollable: find
            .ancestor(
              of: find.text('User settings'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(navigation);
      await session.settle();
      await tester.timedDrag(
        find.byKey(const ValueKey('accessibility-zoom')),
        const Offset(60, 0),
        const Duration(milliseconds: 200),
      );
      await session.settle();

      final after = tester.getSize(find.byType(Scaffold).first).width;
      expect(after, lessThan(before));
      expect(
        tester.getRect(find.byType(Scaffold).first).width,
        closeTo(window.width, 0.5),
      );
    }, size: window);

    testSession(
      'the settings dialog',
      (tester, session) async {
        await tester.tap(find.byKey(const ValueKey('open-connections')));
        await session.settle();

        _expectFollowsDials(tester, find.text('Sign out'));
      },
      size: window,
      accessibility: dials,
    );

    testSession(
      'the message menu',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await session.dispatch('MESSAGE_CREATE', _message('hello'));

        await tester.tapAt(
          tester.getTopLeft(_row) + const Offset(10, 10),
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();

        _expectFollowsDials(tester, find.text('Reply'));
      },
      size: window,
      accessibility: dials,
    );
  });

  group('menus open at the pointer under zoom', () {
    testSession('the message menu', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch('MESSAGE_CREATE', _message('hello'));

      final click = tester.getTopLeft(_row) + const Offset(10, 10);
      await tester.tapAt(click, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final menu = find.byKey(const ValueKey('message-menu-reply'));
      expect(tester.getRect(menu).left, closeTo(click.dx, 1));
    }, accessibility: zoomed);

    testSession('the channel menu', (tester, session) async {
      await tester.tap(
        find.byKey(const ValueKey('space-${SessionHarness.guildId}')),
      );
      await session.settle();

      final click = tester.getCenter(
        find.byKey(const ValueKey('channel-${SessionHarness.channelId}')),
      );
      await tester.tapAt(click, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final menu = find.byWidgetPredicate((widget) => widget is PopupMenuItem);
      expect(tester.getRect(menu.first).left, closeTo(click.dx, 1));
    }, accessibility: zoomed);

    for (final (where, toward) in [
      ('in the middle', Alignment.center),
      ('at the right end', const Alignment(0.95, 0)),
    ]) {
      testSession(
        'the copy and paste menu of the composer, $where',
        (tester, session) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          try {
            await session.openChannel(SessionHarness.channelId);
            await tester.enterText(_composerField, 'hello there');
            await session.settle();

            final click = toward.withinRect(tester.getRect(_composerField));
            await tester.tapAt(click, buttons: kSecondaryButton);
            await session.settle();

            final menu = tester.getRect(
              find
                  .descendant(
                    of: find.byType(DesktopTextSelectionToolbar),
                    matching: find.byType(Material),
                  )
                  .first,
            );
            _expectInside(menu, window);
            expect(menu.inflate(20).contains(click), isTrue, reason: '$menu');
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
        size: window,
        accessibility: zoomed,
      );
    }
  });
}

final _row = find.byKey(const ValueKey('message-900000000000000001'));

final _composerField = find.descendant(
  of: find.byType(MessageComposer),
  matching: find.byType(EditableText),
);

Map<String, Object?> _message(String content) => rawMessage(
  id: '900000000000000001',
  channelId: SessionHarness.channelId,
  guildId: SessionHarness.guildId,
  authorId: SessionHarness.friendId,
  content: content,
);

void _expectInside(Rect drawn, Size window) {
  const slack = 0.5;
  expect(drawn.left, greaterThanOrEqualTo(-slack), reason: '$drawn');
  expect(drawn.top, greaterThanOrEqualTo(-slack), reason: '$drawn');
  expect(
    drawn.right,
    lessThanOrEqualTo(window.width + slack),
    reason: '$drawn',
  );
  expect(
    drawn.bottom,
    lessThanOrEqualTo(window.height + slack),
    reason: '$drawn',
  );
}

/// This text is drawn 1.4 times its laid out size, with a font scale of 1.25,
/// and animations hold still around it.
void _expectFollowsDials(WidgetTester tester, Finder text) {
  final drawnHeight = tester.getRect(text).height;
  final laidOutHeight = tester.getSize(text).height;
  expect(drawnHeight / laidOutHeight, closeTo(1.4, 0.01));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  expect(paragraph.textScaler.scale(10), closeTo(12.5, 0.01));
  expect(MediaQuery.disableAnimationsOf(tester.element(text)), isTrue);
}
