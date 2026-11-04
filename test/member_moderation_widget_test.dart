import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_member_admin_controller.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flucord/src/presentation/widgets/member_moderation_section.dart';
import 'package:flucord/src/presentation/widgets/member_profile_card.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/guild_settings_fixtures.dart';

void main() {
  testWidgets('the moderation block grants and revokes a role', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeGuildManagementRepository();
    final workspace = guildWorkspace();
    final controller = GuildMemberAdminController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
      userId: lowMemberId,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    final memberRole = find.byKey(const ValueKey('member-role-member'));
    expect(memberRole, findsOneWidget);
    await tester.tap(memberRole);
    await tester.pumpAndSettle();
    expect(repository.calls, contains('grantMemberRole'));

    await tester.tap(memberRole);
    await tester.pumpAndSettle();
    expect(repository.calls, contains('revokeMemberRole'));
  });

  testWidgets('the moderation block renames a member', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeGuildManagementRepository();
    final workspace = guildWorkspace();
    final controller = GuildMemberAdminController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
      userId: lowMemberId,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('member-nickname')),
      'Forge Ada',
    );
    await tester.tap(find.byKey(const ValueKey('member-nickname-save')));
    await tester.pumpAndSettle();

    expect(repository.calls, contains('updateMember'));
    expect(repository.memberProfiles[lowMemberId]?.nickname, 'Forge Ada');
  });

  testWidgets('the moderation block times a member out and lifts it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeGuildManagementRepository();
    final workspace = guildWorkspace();
    final controller = GuildMemberAdminController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
      userId: lowMemberId,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    final apply = find.byKey(const ValueKey('member-timeout-apply'));
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(repository.calls, contains('updateMember'));
    expect(repository.memberProfiles[lowMemberId]?.timeoutUntil, isNotNull);

    // The timeout now on record, the block offers the lift instead.
    final lift = find.byKey(const ValueKey('member-timeout-lift'));
    await tester.ensureVisible(lift);
    await tester.pumpAndSettle();
    expect(lift, findsOneWidget);
    await tester.tap(lift);
    await tester.pumpAndSettle();
    expect(repository.memberProfiles[lowMemberId]?.timeoutUntil, isNull);
  });

  testWidgets('kick and ban ask before they act', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeGuildManagementRepository();
    final workspace = guildWorkspace();
    final controller = GuildMemberAdminController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
      userId: lowMemberId,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    final kick = find.byKey(const ValueKey('member-kick'));
    await tester.ensureVisible(kick);
    await tester.pumpAndSettle();
    await tester.tap(kick);
    await tester.pumpAndSettle();
    expect(repository.calls, isNot(contains('kickMember')));
    await tester.tap(find.byKey(const ValueKey('member-kick-confirm')));
    await tester.pumpAndSettle();
    expect(repository.calls, contains('kickMember'));

    final ban = find.byKey(const ValueKey('member-ban'));
    await tester.ensureVisible(ban);
    await tester.pumpAndSettle();
    await tester.tap(ban);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-ban-confirm')));
    await tester.pumpAndSettle();
    expect(repository.bannedRequest!.userIds, [lowMemberId]);
  });

  testWidgets('an account with no authority sees no moderation block', (
    tester,
  ) async {
    final repository = FakeGuildManagementRepository();
    final workspace = guildWorkspace(
      moderatorPermissions: DiscordPermissions.viewChannel,
    );
    final controller = GuildMemberAdminController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
      userId: highMemberId,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('member-kick')), findsNothing);
    expect(find.byKey(const ValueKey('member-ban')), findsNothing);
    expect(find.byKey(const ValueKey('member-timeout-apply')), findsNothing);
    expect(find.byKey(const ValueKey('member-role-member')), findsNothing);
    expect(repository.calls, contains('loadMember'));
  });

  testWidgets('the card offers "+" to a moderator, and it gives the role', (
    tester,
  ) async {
    final repository = await _pumpCard(tester);

    await tester.tap(find.byKey(const ValueKey('profile-card-add-role')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('profile-card-role-choice-member')),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, contains('grantMemberRole'));
  });

  testWidgets('the card opens the moderation block from its menu', (
    tester,
  ) async {
    await _pumpCard(tester);

    await tester.tap(find.byKey(const ValueKey('profile-card-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-card-moderate')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('member-kick')), findsOneWidget);
  });

  testWidgets('a card seen without authority has no "+" and no Moderate', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      moderatorPermissions: DiscordPermissions.viewChannel,
    );

    expect(find.byKey(const ValueKey('profile-card-add-role')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profile-card-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-card-moderate')), findsNothing);
  });
}

Widget _host(GuildMemberAdminController controller) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Center(
      child: SingleChildScrollView(
        child: MemberModerationSection(controller: controller),
      ),
    ),
  ),
);

/// The card for Ada, a member of the guild, as [moderatorPermissions] sees
/// her. The card owns the controller it builds.
Future<FakeGuildManagementRepository> _pumpCard(
  WidgetTester tester, {
  BigInt? moderatorPermissions,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = FakeGuildManagementRepository();
  final workspace = moderatorPermissions == null
      ? guildWorkspace()
      : guildWorkspace(moderatorPermissions: moderatorPermissions);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: MemberProfileCard(
            member: workspace.memberById(lowMemberId),
            spaceId: guildId,
            workspace: workspace,
            moderationBuilder: () => GuildMemberAdminController(
              repository,
              WorkspacePermissions(
                workspace,
                memberId: moderatorId,
              ).administrationOf(guildId),
              guildId: guildId,
              userId: lowMemberId,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}
