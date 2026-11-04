import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_user_settings_proto.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/presentation/conversation_pane.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/session_harness.dart';

/// The shell draws chat and the member list in one card, the canvas. The
/// rail and the channel sidebar stay outside it, on the darkest background.
void main() {
  const window = Size(1440, 900);
  final card = find.byKey(const ValueKey('canvas-card'));
  final rail = find.byKey(const ValueKey('server-rail'));
  final sidebar = find.byKey(const ValueKey('channel-sidebar'));

  Finder inCard(Finder finder) => find.descendant(of: card, matching: finder);
  Container containerOf(WidgetTester tester, Finder finder) =>
      tester.widget<Container>(finder);

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

  testSession(
    'the card is the canvas, with a thin border and clipped corners',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      final surfaces = tester.element(card).surfaces;
      final look = containerOf(tester, card);

      expect(
        look.decoration,
        BoxDecoration(
          color: surfaces.canvas,
          borderRadius: FlucordRadius.large,
        ),
      );
      expect(
        look.foregroundDecoration,
        BoxDecoration(
          border: Border.all(color: surfaces.border),
          borderRadius: FlucordRadius.large,
        ),
      );
      expect(look.clipBehavior, isNot(Clip.none));
    },
    size: window,
  );

  testSession('the rail and the channel sidebar share the rail, no lines', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    final surfaces = tester.element(card).surfaces;

    for (final navigation in [rail, sidebar]) {
      expect(
        containerOf(tester, navigation).decoration,
        BoxDecoration(color: surfaces.rail),
      );
    }
    expect(tester.getRect(rail).right, tester.getRect(sidebar).left);
  }, size: window);

  testSession('with the member list hidden, the chat fills the card', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await tester.tap(find.byKey(const ValueKey('toggle-members')));
    await session.settle();

    expect(find.byType(MemberSidebar), findsNothing);
    expect(tester.getRect(find.byType(ConversationPane)), tester.getRect(card));
  }, size: window);

  testSession('a direct message opens inside the card too', (
    tester,
    session,
  ) async {
    await session.openChannel(
      SessionHarness.dmChannelId,
      space: 'direct-messages',
    );

    expect(inCard(find.byType(ConversationPane)), findsOneWidget);
    expect(tester.getRect(find.byType(ConversationPane)), tester.getRect(card));
  }, size: window);

  testSession(
    'with the dark sidebar on the light theme, all navigation turns dark',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      final dark = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
      final frame = tester.widget<ColoredBox>(
        find.ancestor(of: card, matching: find.byType(ColoredBox)).first,
      );

      // The chat stays light; what is around it is one dark ground.
      expect(Theme.of(tester.element(card)).brightness, Brightness.light);
      for (final navigation in [rail, sidebar]) {
        expect(
          containerOf(tester, navigation).decoration,
          BoxDecoration(color: dark.rail),
        );
      }
      expect(frame.color, dark.rail);
    },
    size: window,
    ready: SessionHarness.defaultReady()
      ..['user_settings_proto'] = _lightWithDarkSidebar(),
  );
}

String _lightWithDarkSidebar() {
  const lightOnWire = 2;
  return DiscordUserSettingsProto.encodeBase64(
    (ProtoMessage()..setMessage(
          PreloadedUserSettingsField.appearance,
          ProtoMessage()
            ..setVarint(AppearanceField.theme, lightOnWire)
            ..setBool(AppearanceField.darkSidebar, true),
        ))
        .encode(),
  );
}
