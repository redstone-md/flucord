import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/server_rail.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders Discord rail activity for DMs and guilds', (
    tester,
  ) async {
    String? selectedSpace;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ServerRail(
            workspace: _workspace,
            selectedSpaceId: CommunitySpace.directMessagesId,
            onSelectSpace: (value) => selectedSpace = value,
            onToggleTheme: () {},
            onOpenConnections: () {},
            sessionMode: SessionMode.discordBot,
            isDark: true,
          ),
        ),
      ),
    );

    expect(_badgeText(tester, CommunitySpace.directMessagesId), '99+');
    expect(_badgeText(tester, 'guild-1'), '3');
    expect(find.byKey(const ValueKey('space-mention-guild-2')), findsNothing);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey(
                'space-indicator-${CommunitySpace.directMessagesId}',
              ),
            ),
          )
          .height,
      28,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('space-indicator-guild-1')))
          .height,
      8,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('space-indicator-guild-2')))
          .height,
      8,
    );

    final dmSemantics = tester.getSemantics(
      find.byKey(
        const ValueKey('space-semantics-${CommunitySpace.directMessagesId}'),
      ),
    );
    final guildSemantics = tester.getSemantics(
      find.byKey(const ValueKey('space-semantics-guild-1')),
    );
    expect(dmSemantics.label, 'Direct Messages, 120 mentions');
    expect(guildSemantics.label, 'Forge, 3 mentions');

    await tester.tap(find.byKey(const ValueKey('space-guild-1')));
    expect(selectedSpace, 'guild-1');
    expect(tester.takeException(), isNull);
  });
}

String _badgeText(WidgetTester tester, String spaceId) {
  final badge = find.byKey(ValueKey('space-mention-$spaceId'));
  return tester
      .widget<Text>(find.descendant(of: badge, matching: find.byType(Text)))
      .data!;
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace.directMessages(),
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
    CommunitySpace(
      id: 'guild-2',
      name: 'Archive',
      monogram: 'AR',
      colorValue: 0xff59636a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'dm-1',
      spaceId: CommunitySpace.directMessagesId,
      name: 'Jack',
      topic: '',
      kind: ChannelKind.text,
      recipientId: 'user-1',
      unread: true,
      mentionCount: 120,
    ),
    ConversationChannel(
      id: 'guild-general',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      mentionCount: 2,
    ),
    ConversationChannel(
      id: 'guild-alerts',
      spaceId: 'guild-1',
      name: 'alerts',
      topic: '',
      kind: ChannelKind.text,
      mentionCount: 1,
    ),
    ConversationChannel(
      id: 'archive-general',
      spaceId: 'guild-2',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      unread: true,
    ),
  ],
  members: const [],
  messages: const [],
  currentMemberId: 'bot-1',
);
