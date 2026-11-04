import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/member_profile_card.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/guild_settings_fixtures.dart';

void main() {
  testWidgets('the server menu opens settings', (tester) async {
    var opened = 0;
    await _pumpSidebar(tester, onOpenServerSettings: () => opened++);
    await tester.tap(find.byKey(const ValueKey('space-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-server-settings')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('there is no server menu when it would be empty', (tester) async {
    await _pumpSidebar(tester);
    expect(find.byKey(const ValueKey('space-menu')), findsNothing);
  });

  testWidgets('direct messages have no server menu', (tester) async {
    await _pumpSidebar(
      tester,
      space: const CommunitySpace.directMessages(),
      onOpenServerSettings: () {},
    );
    expect(find.byKey(const ValueKey('space-menu')), findsNothing);
    expect(find.byKey(const ValueKey('new-direct-message')), findsOneWidget);
  });

  testWidgets('the profile card offers report and block when it can', (
    tester,
  ) async {
    var reported = 0;
    var blocked = 0;
    await _pumpCard(
      tester,
      onReport: () => reported++,
      onBlock: () => blocked++,
    );
    for (final action in ['report-member', 'block-member']) {
      await tester.tap(find.byKey(const ValueKey('profile-card-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(action)));
      await tester.pumpAndSettle();
    }
    expect(reported, 1);
    expect(blocked, 1);
  });

  testWidgets('a transport with no safety plane offers neither', (
    tester,
  ) async {
    await _pumpCard(tester);
    await tester.tap(find.byKey(const ValueKey('profile-card-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-member')), findsNothing);
    expect(find.byKey(const ValueKey('block-member')), findsNothing);
    expect(find.byKey(const ValueKey('copy-member-id')), findsOneWidget);
  });

  testWidgets('the card keeps its actions in a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpCard(tester, onReport: () {}, onBlock: () {});
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('profile-card-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-member')), findsOneWidget);
  });
}

Future<void> _pumpSidebar(
  WidgetTester tester, {
  CommunitySpace? space,
  VoidCallback? onOpenServerSettings,
}) async {
  final workspace = guildWorkspace();
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ChannelSidebar(
          space: space ?? workspace.spaces.single,
          channels: workspace.channelsFor(guildId),
          selectedChannelId: textChannelId,
          onSelectChannel: (_) {},
          sessionMode: SessionMode.demo,
          connectionStatus: RepositoryConnectionStatus.connected,
          categories: workspace.categoriesFor(guildId),
          currentMember: workspace.memberById(workspace.currentMemberId),
          memberOf: workspace.memberOrNull,
          channelOf: workspace.channelOrNull,
          collapsedCategoryIds: const {},
          onToggleCategory: (_) {},
          onNewDirectMessage: () {},
          onOpenServerSettings: onOpenServerSettings,
        ),
      ),
    ),
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  VoidCallback? onReport,
  VoidCallback? onBlock,
}) async {
  final workspace = guildWorkspace();
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: MemberProfileCard(
            member: workspace.memberById(lowMemberId),
            spaceId: guildId,
            onReport: onReport,
            onBlock: onBlock,
          ),
        ),
      ),
    ),
  );
}
