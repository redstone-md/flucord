import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('collapses categories but retains selected and unread channels', (
    tester,
  ) async {
    final controller = WorkspaceController()..reconcile(_workspace);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => ChannelSidebar(
              space: _workspace.spaces.single,
              channels: _workspace.channels,
              selectedChannelId: controller.selectedChannelId,
              onSelectChannel: controller.selectChannel,
              sessionMode: SessionMode.demo,
              connectionStatus: RepositoryConnectionStatus.connected,
              workspace: _workspace,
              collapsedCategoryIds: controller.collapsedCategoryIds,
              onToggleCategory: controller.toggleCategory,
              onNewDirectMessage: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('OPERATIONS'), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-random')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-panel')), findsOneWidget);

    final mention = tester.widget<Container>(
      find.byKey(const ValueKey('channel-mention-alerts')),
    );
    expect((mention.decoration! as BoxDecoration).color, FlucordColors.mention);

    await tester.tap(find.byKey(const ValueKey('category-category-1')));
    await tester.pump();

    expect(controller.collapsedCategoryIds, contains('category-1'));
    expect(find.byKey(const ValueKey('channel-general')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-alerts')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-random')), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('category-category-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('channel-random')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  categories: const [
    ChannelCategory(
      id: 'category-1',
      spaceId: 'guild-1',
      name: 'Operations',
      position: 1,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'general',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      position: 1,
      parentId: 'category-1',
    ),
    ConversationChannel(
      id: 'alerts',
      spaceId: 'guild-1',
      name: 'alerts',
      topic: '',
      kind: ChannelKind.text,
      position: 2,
      parentId: 'category-1',
      unread: true,
      mentionCount: 2,
    ),
    ConversationChannel(
      id: 'random',
      spaceId: 'guild-1',
      name: 'random',
      topic: '',
      kind: ChannelKind.text,
      position: 3,
      parentId: 'category-1',
    ),
  ],
  members: const [
    Member(
      id: 'bot-1',
      displayName: 'Flucord Bot',
      initials: 'FB',
      role: 'Discord bot',
      presence: Presence.online,
      colorValue: 0xff5865f2,
    ),
  ],
  messages: const [],
  currentMemberId: 'bot-1',
);
