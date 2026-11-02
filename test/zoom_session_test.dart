import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app.dart';
import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/accessibility.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';
import 'support/zoomed_app.dart';

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

    testSession('the server menu on the rail', (tester, session) async {
      final click = tester.getCenter(
        find.byKey(const ValueKey('space-${SessionHarness.guildId}')),
      );
      await tester.tapAt(click, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final menu = find.byKey(const ValueKey('server-menu-mark-read'));
      expect(tester.getRect(menu).left, closeTo(click.dx, 1));
    }, accessibility: zoomed);

    testSession('the reaction picker of the message menu', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch('MESSAGE_CREATE', _message('hello'));

      final click = tester.getTopLeft(_row) + const Offset(10, 10);
      await tester.tapAt(click, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-menu-add-reaction')));
      await tester.pumpAndSettle();

      final picker = tester.getRect(find.byKey(const ValueKey('emoji-picker')));
      expect(picker.left, closeTo(click.dx, 1));
      _expectInside(picker, window);
    }, accessibility: zoomed);

    for (final (where, toward) in [
      ('in the middle', Alignment.center),
      ('at the right end', const Alignment(0.95, 0)),
    ]) {
      testSession(
        'the copy and paste menu of the composer, $where',
        (tester, session) async {
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
        },
        size: window,
        accessibility: zoomed,
        platform: TargetPlatform.linux,
      );
    }
  });

  group('at the smallest window', () {
    for (final dials in const [
      AccessibilitySettings(),
      AccessibilitySettings(zoom: 1.4),
      AccessibilitySettings(zoom: 1.4, fontScale: 1.5),
      AccessibilitySettings(zoom: 0.8, fontScale: 1.5),
    ]) {
      final name = 'zoom ${dials.zoom}, font ${dials.fontScale}';

      testSession(
        'everything fits at $name',
        (tester, session) async {
          await session.openChannel(SessionHarness.channelId);

          for (final pane in [
            find.byKey(const ValueKey('channel-sidebar')),
            find.byKey(const ValueKey('account-panel')),
            find.byType(MessageComposer),
          ]) {
            _expectInside(tester.getRect(pane), _smallestWindow);
          }
          final menu = tester.getRect(
            find.byKey(const ValueKey('composer-menu')),
          );
          final emoji = tester.getRect(
            find.byKey(const ValueKey('open-emoji-picker')),
          );
          expect(menu.overlaps(emoji), isFalse, reason: '$menu $emoji');
        },
        size: _smallestWindow,
        accessibility: dials,
      );

      testSession(
        'the settings dialog stays on screen at $name',
        (tester, session) async {
          await tester.tap(find.byKey(const ValueKey('open-connections')));
          await session.settle();

          _expectInside(
            tester.getRect(find.byType(Dialog).last),
            _smallestWindow,
          );
        },
        size: _smallestWindow,
        accessibility: dials,
      );
      testSession(
        'the user settings window stays on screen at $name',
        (tester, session) async {
          await tester.tap(find.byKey(const ValueKey('open-user-settings')));
          await session.settle();

          _expectInside(
            tester.getRect(find.byType(Dialog).last),
            _smallestWindow,
          );
        },
        size: _smallestWindow,
        accessibility: dials,
      );

      testSession(
        'the emoji picker stays on screen at $name',
        (tester, session) async {
          await session.openChannel(SessionHarness.channelId);

          await tester.tap(find.byKey(const ValueKey('open-emoji-picker')));
          await session.settle();

          _expectInside(
            tester.getRect(find.byKey(const ValueKey('emoji-picker'))),
            _smallestWindow,
          );
        },
        size: _smallestWindow,
        accessibility: dials,
      );

      testSession(
        'the GIF picker fits at $name',
        (tester, session) async {
          await session.openChannel(SessionHarness.channelId);

          await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
          await session.settle();

          _expectInside(
            tester.getRect(find.widgetWithText(TextField, 'Search Tenor')),
            _smallestWindow,
          );
        },
        size: _smallestWindow,
        accessibility: dials,
      );

      testWidgets('the voice bar and account panel stay visible at $name', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(_smallestWindow);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        // Voice runs in the demo: the session harness has no DAVE service.
        await tester.pumpWidget(
          FlucordApp(
            bootstrap: AppBootstrap(
              initialSessionMode: SessionMode.demo,
              enableBotTransport: false,
              accessibilityRepository: FixedDials(dials),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        final channel = find.byKey(const ValueKey('channel-forge-voice'));
        await tester.ensureVisible(channel);
        await tester.pumpAndSettle();
        await tester.tap(channel);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('voice-channel-join')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // At the largest font the bar is taller than its share of a short
        // window and scrolls, so its leave button has to be reachable.
        final leave = find.byKey(const ValueKey('voice-bar-disconnect'));
        await tester.ensureVisible(leave);
        await tester.pumpAndSettle();

        final bar = tester.getRect(
          find.byKey(const ValueKey('voice-connection-bar')),
        );
        expect(bar.top, lessThan(_smallestWindow.height));
        _expectInside(tester.getRect(leave), _smallestWindow);
        _expectInside(
          tester.getRect(find.byKey(const ValueKey('account-panel'))),
          _smallestWindow,
        );
      });

      testSession(
        'the connection banner and account panel stay visible at $name',
        (tester, session) async {
          await session.openChannel(SessionHarness.channelId);

          session.socket.dropConnection(code: 4000);
          await session.settle();

          _expectInside(
            tester.getRect(find.textContaining('Reconnecting')),
            _smallestWindow,
          );
          _expectInside(
            tester.getRect(find.byKey(const ValueKey('account-panel'))),
            _smallestWindow,
          );
          _expectInside(
            tester.getRect(find.byType(MessageComposer)),
            _smallestWindow,
          );
        },
        size: _smallestWindow,
        accessibility: dials,
      );

      testSession(
        'the screen after a failed launch fits at $name',
        (tester, session) async {
          await session.relaunchUnreachable();

          _expectInside(
            tester.getRect(find.byKey(const ValueKey('disconnected-retry'))),
            _smallestWindow,
          );
        },
        size: _smallestWindow,
        accessibility: dials,
      );

      // At 0.8 the window is wide enough for the panel to sit beside it.
      if (dials.zoom < 1) continue;

      testSession(
        'a side panel covers the conversation and keeps its text at $name',
        (tester, session) async {
          await session.openChannel(SessionHarness.channelId);
          await tester.enterText(_composerField, 'half a thought');
          await session.settle();

          await tester.tap(find.byKey(const ValueKey('toggle-pins')));
          await session.settle();

          final panel = tester.getRect(
            find.byKey(const ValueKey('pinned-messages-panel')),
          );
          final sidebar = tester.getRect(
            find.byKey(const ValueKey('channel-sidebar')),
          );
          expect(panel.left, closeTo(sidebar.right, 0.5));
          expect(panel.right, closeTo(_smallestWindow.width, 0.5));
          expect(find.byKey(const ValueKey('composer-menu')), findsNothing);

          await tester.tap(find.byKey(const ValueKey('close-pins-panel')));
          await session.settle();

          expect(find.text('half a thought'), findsOneWidget);
        },
        size: _smallestWindow,
        accessibility: dials,
      );
    }
  });
}

/// The minimum of 940 by 500 is the whole window on Windows and macOS, so the
/// title bar and the frame come off it. This is what is left on Windows, the
/// platform with the thickest frame.
const _smallestWindow = Size(924, 461);

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
