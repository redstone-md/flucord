import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/workspace_activity.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/direct_message_views.dart';
import 'package:flucord/src/presentation/widgets/server_rail.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets(
    'renders the direct inbox as identities instead of hash channels',
    (tester) async {
      var newMessages = 0;
      String? selectedSpace;
      await tester.binding.setSurfaceSize(const Size(700, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: Row(
              children: [
                ServerRail(
                  spaces: _workspace.spaces,
                  activity: _workspace.activityBySpace(),
                  selectedSpaceId: CommunitySpace.directMessagesId,
                  onSelectSpace: (value) => selectedSpace = value,
                  onToggleTheme: () {},
                  onOpenConnections: () {},
                  sessionMode: SessionMode.discord,
                  isDark: true,
                ),
                ChannelSidebar(
                  space: _workspace.spaceById(CommunitySpace.directMessagesId),
                  channels: _workspace.channelsFor(
                    CommunitySpace.directMessagesId,
                  ),
                  selectedChannelId: 'dm-1',
                  onSelectChannel: (_) {},
                  sessionMode: SessionMode.discord,
                  connectionStatus: RepositoryConnectionStatus.connected,
                  categories: _workspace.categoriesFor(
                    CommunitySpace.directMessagesId,
                  ),
                  currentMember: _workspace.memberById(
                    _workspace.currentMemberId,
                  ),
                  memberOf: _workspace.memberOrNull,
                  channelOf: _workspace.channelOrNull,
                  collapsedCategoryIds: const {},
                  onToggleCategory: (_) {},
                  onNewDirectMessage: () => newMessages++,
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Direct Messages'), findsOneWidget);
      expect(find.text('Jack'), findsOneWidget);
      expect(find.text('Flucord Bot'), findsOneWidget);
      expect(find.byKey(const ValueKey('server-rail')), findsOneWidget);
      expect(find.byKey(const ValueKey('channel-sidebar')), findsOneWidget);
      expect(find.byKey(const ValueKey('account-panel')), findsOneWidget);
      expect(find.byIcon(Icons.tag), findsNothing);

      final guildButton = find.byKey(const ValueKey('space-guild-1'));
      final guildSurface = find.descendant(
        of: guildButton,
        matching: find.byType(AnimatedContainer),
      );
      var decoration = tester
          .widget<AnimatedContainer>(guildSurface)
          .decoration!;
      expect(
        (decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(22),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(guildButton));
      await tester.pump(const Duration(milliseconds: 160));
      decoration = tester.widget<AnimatedContainer>(guildSurface).decoration!;
      expect(
        (decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(14),
      );
      await mouse.removePointer();

      await tester.tap(find.byKey(const ValueKey('new-direct-message')));
      await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
      expect(newMessages, 1);
      expect(selectedSpace, CommunitySpace.directMessagesId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('validates a Discord snowflake before opening a DM', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => const DirectMessageDialog(),
              ),
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('direct-message-user-id'));

    await tester.enterText(input, '123');
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('Enter a valid Discord user ID'), findsOneWidget);

    await tester.enterText(input, '123456789012345678');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DirectMessageDialog), findsNothing);
  });

  testWidgets('empty direct inbox exposes one stable creation action', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: DirectMessagesEmptyView(onNewMessage: () => opened = true),
        ),
      ),
    );

    expect(find.text('No direct messages'), findsOneWidget);
    await tester.tap(find.text('New message'));
    expect(opened, isTrue);
  });
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace.directMessages(),
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff765341,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'dm-1',
      spaceId: CommunitySpace.directMessagesId,
      name: 'Jack',
      topic: 'Direct message with Jack',
      kind: ChannelKind.text,
      recipientId: 'user-1',
    ),
  ],
  members: const [
    Member(
      id: 'bot-1',
      displayName: 'Flucord Bot',
      initials: 'FB',
      role: 'Discord bot',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
    Member(
      id: 'user-1',
      displayName: 'Jack',
      initials: 'J',
      role: 'Direct message',
      presence: Presence.offline,
      colorValue: 0xff59636a,
      spaceIds: {CommunitySpace.directMessagesId},
    ),
  ],
  messages: const [],
  currentMemberId: 'bot-1',
);
