import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/inbox_catalog.dart';
import 'package:flucord/src/application/voice_channel_surface.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/chat_header.dart';
import 'package:flucord/src/presentation/widgets/count_badge.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';

import 'support/flucord_icon_finder.dart';

/// The chat header is one clean 48 px line: the channel, a muted one-line
/// topic, 28 px buttons and a recessed search field.
void main() {
  const topic =
      'Everything about the build, the release and the tools we use every '
      'day, and a few things that have nothing to do with any of them.';
  const channel = ConversationChannel(
    id: 'general',
    spaceId: 'forge',
    name: 'general',
    topic: topic,
    kind: ChannelKind.text,
  );

  final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
  final members = find.byKey(const ValueKey('toggle-members'));
  final search = find.byKey(const ValueKey('message-search'));

  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

  testWidgets('is one 48 px line with the name and a muted one-line topic', (
    tester,
  ) async {
    await _pump(tester, channel: channel);

    expect(tester.getSize(find.byType(ChatHeader)).height, 48);
    expect(
      tester.getSize(find.text(topic)).height,
      FlucordTextRole.caption.lineHeight,
      reason: 'a long topic is cut to one line, not wrapped',
    );
    expect(styleOf(tester, topic).color, surfaces.captionText);
    expect(styleOf(tester, 'general').fontWeight, FontWeight.w500);
    expect(styleOf(tester, 'general').color, surfaces.text);
  });

  testWidgets('draws no divider when the channel has no topic', (tester) async {
    await _pump(
      tester,
      channel: const ConversationChannel(
        id: 'general',
        spaceId: 'forge',
        name: 'general',
        topic: '',
        kind: ChannelKind.text,
      ),
    );

    expect(find.byKey(const ValueKey('chat-header-divider')), findsNothing);
  });

  testWidgets('its buttons are 28 px squares', (tester) async {
    await _pump(tester, channel: channel);

    for (final key in [
      'toggle-threads',
      'toggle-pins',
      'toggle-members',
      'open-inbox',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))),
        const Size.square(28),
        reason: key,
      );
    }
  });

  testWidgets('the members button is filled while the list is open', (
    tester,
  ) async {
    final fill = surfaces.text.withValues(alpha: 0.06);

    await _pump(tester, channel: channel, showMembers: false);
    expect(tester.renderObject(members), isNot(paints..rrect(color: fill)));

    await _pump(tester, channel: channel, showMembers: true);
    expect(tester.renderObject(members), paints..rrect(color: fill));
  });

  testWidgets('the inbox shows its mentions with the shared badge', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: channel,
      inbox: const InboxSummary(unreadChannelCount: 1, mentionCount: 3),
    );

    expect(
      find.descendant(
        of: find.byType(ChatHeader),
        matching: find.byType(CountBadge),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the search field is 200 by 28 and offers a clear once typed in',
    (tester) async {
      await _pump(tester, channel: channel);

      expect(tester.getSize(search), const Size(200, 28));
      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(search, 'release');
      await tester.pump();

      expect(find.byTooltip('Clear search'), findsOneWidget);
    },
  );

  // No key focuses search, and Ctrl K opens the quick switcher, so the field
  // names no shortcut.
  testWidgets('the search field names no shortcut', (tester) async {
    await _pump(tester, channel: channel);

    expect(find.text('Ctrl K'), findsNothing);
    expect(find.text('⌘K'), findsNothing);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a DM header puts the person before the name, not an icon', (
    tester,
  ) async {
    const person = SizedBox.square(key: ValueKey('dm-avatar'), dimension: 24);
    await _pump(
      tester,
      channel: const ConversationChannel(
        id: 'dm',
        spaceId: '@me',
        name: 'Jack',
        topic: '',
        kind: ChannelKind.text,
        recipientId: 'jack',
      ),
      leading: person,
    );

    final avatar = tester.getRect(find.byKey(const ValueKey('dm-avatar')));
    expect(avatar.right, lessThan(tester.getRect(find.text('Jack')).left));
    expect(findFlucordIcon(FlucordIcons.textChannel), findsNothing);
    expect(findFlucordIcon(FlucordIcons.person), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ConversationChannel channel,
  bool showMembers = false,
  InboxSummary inbox = const InboxSummary(
    unreadChannelCount: 0,
    mentionCount: 0,
  ),
  Widget? leading,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: ChatHeader(
            channel: channel,
            channels: [channel],
            leading: leading,
            query: '',
            showCompactPicker: false,
            showsMessages: true,
            voiceSurface: VoiceChannelSurface.chat,
            allowMemberPanel: true,
            allowThreadPanel: true,
            showMembers: showMembers,
            showPins: false,
            showThreads: false,
            inboxSummary: inbox,
            onSelectChannel: (_) {},
            onSelectVoiceSurface: (_) {},
            onQueryChanged: (_) {},
            onSubmitQuery: null,
            onToggleMembers: () {},
            onTogglePins: () {},
            onToggleThreads: () {},
            onOpenInbox: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
