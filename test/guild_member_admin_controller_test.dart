import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_member_admin_controller.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';

import 'support/guild_settings_fixtures.dart';

void main() {
  GuildMemberAdminController controller({
    String userId = lowMemberId,
    BigInt? permissions,
    FakeGuildManagementRepository? repository,
  }) {
    final workspace = guildWorkspace(
      moderatorPermissions: permissions ?? allModerationPermissions,
    );
    final admin = GuildMemberAdminController(
      repository ?? FakeGuildManagementRepository(),
      WorkspacePermissions(
        workspace,
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
      userId: userId,
    );
    addTearDown(admin.dispose);
    return admin;
  }

  test('loads the member and the guild roles together', () async {
    final repository = FakeGuildManagementRepository();
    final admin = controller(repository: repository);
    await admin.load();

    expect(admin.profile, isNotNull);
    // Highest first, the way the popover lists them.
    expect(admin.roles.map((role) => role.id), [
      'moderator',
      'member',
      guildId,
    ]);
  });

  group('roles', () {
    test('grants a role the moderator may hand out', () async {
      final repository = FakeGuildManagementRepository();
      // The member holds nothing, so the ordinary member role is a real
      // grant rather than a no-op the controller would refuse to send.
      final admin = controller(repository: repository);
      await admin.load();

      final memberRole = admin.roles.firstWhere((role) => role.id == 'member');
      expect(admin.canAssignRole(memberRole), isTrue);
      expect(await admin.grantRole(memberRole), isTrue);
      expect(admin.profile!.roleIds, contains('member'));
      expect(repository.calls, contains('grantMemberRole'));
    });

    test('revokes one role without touching the others', () async {
      final repository = FakeGuildManagementRepository()
        ..includeLowRoles = true;
      repository.memberProfiles[lowMemberId] = GuildMemberProfile(
        userId: lowMemberId,
        guildId: guildId,
        roleIds: const ['helper', 'member'],
      );
      final admin = controller(repository: repository);
      await admin.load();

      final helper = admin.roles.firstWhere((role) => role.id == 'helper');
      expect(await admin.revokeRole(helper), isTrue);
      expect(admin.profile!.roleIds, ['member']);
      expect(repository.calls, contains('revokeMemberRole'));
    });

    test('a role the moderator does not outrank is never offered', () async {
      final repository = FakeGuildManagementRepository();
      final admin = controller(repository: repository);
      await admin.load();
      repository.calls.clear();

      // Their own role sits at their own highest position, so handing it out
      // would be handing out their own authority.
      final own = admin.roles.firstWhere((role) => role.id == 'moderator');
      expect(admin.canAssignRole(own), isFalse);
      expect(await admin.grantRole(own), isFalse);
      expect(await admin.revokeRole(own), isFalse);
      final everyone = admin.roles.firstWhere((role) => role.id == guildId);
      expect(admin.canAssignRole(everyone), isFalse);
      expect(repository.calls, isEmpty);
    });

    test('an integration-managed role is never offered', () async {
      final repository = FakeGuildManagementRepository()..includeManaged = true;
      final admin = controller(repository: repository);
      await admin.load();

      final managed = admin.roles.firstWhere((role) => role.id == 'bot');
      expect(admin.canAssignRole(managed), isFalse);
    });

    test(
      'a member who outranks the moderator gets no actions at all',
      () async {
        final admin = controller(userId: highMemberId);
        await admin.load();

        expect(admin.roles.where(admin.canAssignRole), isEmpty);
        expect(admin.hasAnyAction, isFalse);
      },
    );
  });

  group('nickname', () {
    test('sets and clears a nickname', () async {
      final repository = FakeGuildManagementRepository();
      final admin = controller(repository: repository);
      await admin.load();

      expect(await admin.setNickname('Forge Ada'), isTrue);
      expect(admin.profile!.nickname, 'Forge Ada');

      expect(await admin.setNickname('  '), isTrue);
      expect(admin.profile!.nickname, isNull);
      expect(repository.calls, contains('updateMember'));
    });

    test('renaming without MANAGE_NICKNAMES is refused', () async {
      final repository = FakeGuildManagementRepository();
      final admin = controller(
        repository: repository,
        permissions: DiscordPermissions.combine([
          DiscordPermissions.manageRoles,
          DiscordPermissions.kickMembers,
        ]),
      );
      await admin.load();

      expect(await admin.setNickname('Forge Ada'), isFalse);
      expect(repository.calls, isNot(contains('updateMember')));
    });
  });

  group('timeout', () {
    test('applies a timeout and lifts it again', () async {
      final repository = FakeGuildManagementRepository();
      final admin = controller(repository: repository);
      await admin.load();

      final now = DateTime.utc(2026, 9, 14, 12);
      expect(
        await admin.timeoutMember(const Duration(minutes: 10), now: now),
        isTrue,
      );
      expect(admin.profile!.timeoutUntil, now.add(const Duration(minutes: 10)));
      expect(admin.profile!.isTimedOutAt(now), isTrue);

      expect(await admin.liftTimeout(), isTrue);
      expect(admin.profile!.timeoutUntil, isNull);
      expect(repository.calls, contains('updateMember'));
    });

    test('lifting without a timeout asks nothing', () async {
      final repository = FakeGuildManagementRepository();
      final admin = controller(repository: repository);
      await admin.load();

      expect(await admin.liftTimeout(), isFalse);
      expect(repository.calls, isNot(contains('updateMember')));
    });

    test('a member above the moderator cannot be timed out', () async {
      final repository = FakeGuildManagementRepository();
      final admin = controller(userId: highMemberId, repository: repository);
      await admin.load();

      expect(await admin.timeoutMember(const Duration(minutes: 10)), isFalse);
      expect(repository.calls, isNot(contains('updateMember')));
    });

    test('the permission bit is required', () async {
      final repository = FakeGuildManagementRepository();
      final admin = controller(
        repository: repository,
        permissions: DiscordPermissions.kickMembers,
      );
      await admin.load();

      expect(await admin.timeoutMember(const Duration(minutes: 10)), isFalse);
      expect(repository.calls, isNot(contains('updateMember')));
    });
  });

  test('kicks and bans through the shared routes', () async {
    final repository = FakeGuildManagementRepository();
    final admin = controller(repository: repository);
    await admin.load();

    expect(await admin.kickMember(), isTrue);
    expect(repository.calls, contains('kickMember'));
    expect(await admin.banMember(), isTrue);
    expect(repository.bannedRequest!.userIds, [lowMemberId]);
  });

  test('a failed action keeps the popover open with the error', () async {
    final repository = FakeGuildManagementRepository();
    final admin = controller(repository: repository);
    await admin.load();
    repository.failNext = true;

    expect(await admin.kickMember(), isFalse);
    expect(admin.error, isNotNull);
    expect(admin.isBusy, isFalse);
  });
}
