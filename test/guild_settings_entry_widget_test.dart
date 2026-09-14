import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/member_profile_popover.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/guild_settings_fixtures.dart';

void main() {
  testWidgets('the sidebar shows a settings gear only when it opens', (
    tester,
  ) async {
    var opened = 0;
    await _pumpSidebar(tester, onOpenServerSettings: () => opened++);
    await tester.tap(find.byKey(const ValueKey('open-server-settings')));
    expect(opened, 1);
  });

  testWidgets('the gear is absent when nothing can be administered', (
    tester,
  ) async {
    await _pumpSidebar(tester);
    expect(find.byKey(const ValueKey('open-server-settings')), findsNothing);
  });

  testWidgets('the gear never appears on direct messages', (tester) async {
    await _pumpSidebar(
      tester,
      space: const CommunitySpace.directMessages(),
      onOpenServerSettings: () {},
    );
    expect(find.byKey(const ValueKey('open-server-settings')), findsNothing);
    expect(find.byKey(const ValueKey('new-direct-message')), findsOneWidget);
  });

  testWidgets('the profile popover offers report and block when it can', (
    tester,
  ) async {
    var reported = 0;
    var blocked = 0;
    await _pumpPopover(
      tester,
      onReport: () => reported++,
      onBlock: () => blocked++,
    );
    await tester.tap(find.byKey(const ValueKey('report-member')));
    await tester.tap(find.byKey(const ValueKey('block-member')));
    expect(reported, 1);
    expect(blocked, 1);
  });

  testWidgets('a transport with no safety plane offers neither', (
    tester,
  ) async {
    await _pumpPopover(tester);
    expect(find.byKey(const ValueKey('report-member')), findsNothing);
    expect(find.byKey(const ValueKey('block-member')), findsNothing);
    expect(find.byKey(const ValueKey('message-member')), findsOneWidget);
  });

  testWidgets('the popover keeps its actions in a narrow window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpPopover(tester, onReport: () {}, onBlock: () {});
    expect(tester.takeException(), isNull);
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

Future<void> _pumpPopover(
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
          child: MemberProfilePopover(
            member: workspace.memberById(lowMemberId),
            spaceId: guildId,
            canMessage: true,
            onMessage: () {},
            onReport: onReport,
            onBlock: onBlock,
          ),
        ),
      ),
    ),
  );
}
