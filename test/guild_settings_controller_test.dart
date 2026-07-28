import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_settings_controller.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/automod_rule_editing.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';

import 'support/guild_settings_fixtures.dart';

part 'guild_settings_automod_cases.dart';
part 'guild_settings_structure_cases.dart';

void main() {
  _automodControllerCases();

  test('only the permitted sections are listed', () {
    final controller = _controller(
      permissions: DiscordPermissions.combine([
        DiscordPermissions.viewChannel,
        DiscordPermissions.banMembers,
        DiscordPermissions.viewAuditLog,
      ]),
    );
    expect(controller.availableSections, [
      GuildSettingsSection.bans,
      GuildSettingsSection.auditLog,
    ]);
  });

  test('a section the account cannot use never loads', () async {
    final repository = FakeGuildManagementRepository();
    final controller = _controller(
      repository: repository,
      permissions: DiscordPermissions.viewChannel,
    );
    await controller.openSection(GuildSettingsSection.overview);
    expect(repository.calls, isEmpty);
    expect(controller.section, GuildSettingsSection.overview);
  });

  test('a section loads once and only refetches when asked', () async {
    final repository = FakeGuildManagementRepository();
    final controller = _controller(repository: repository);
    await controller.openSection(GuildSettingsSection.overview);
    expect(controller.overview!.name, 'The Forge');
    await controller.openSection(GuildSettingsSection.overview);
    expect(repository.calls.where((call) => call == 'loadGuildOverview'), [
      'loadGuildOverview',
    ]);
    await controller.load(GuildSettingsSection.overview, refresh: true);
    expect(
      repository.calls.where((call) => call == 'loadGuildOverview'),
      hasLength(2),
    );
  });

  test('a failed load leaves a retryable error', () async {
    final repository = FakeGuildManagementRepository()..failNext = true;
    final controller = _controller(repository: repository);
    await controller.openSection(GuildSettingsSection.overview);
    expect(controller.errorFor(GuildSettingsSection.overview), isNotNull);
    expect(controller.isLoading(GuildSettingsSection.overview), isFalse);
    await controller.load(GuildSettingsSection.overview, refresh: true);
    expect(controller.errorFor(GuildSettingsSection.overview), isNull);
    expect(controller.overview, isNotNull);
  });

  test('the channels section reads from the workspace, not the wire', () async {
    final repository = FakeGuildManagementRepository();
    final controller = _controller(repository: repository);
    await controller.openSection(GuildSettingsSection.channels);
    expect(repository.calls, isEmpty);
    expect(controller.errorFor(GuildSettingsSection.channels), isNull);
  });

  group('overview', () {
    test('an empty patch is never sent', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      expect(await controller.saveOverview(GuildOverviewPatch()), isFalse);
      expect(repository.calls, isEmpty);
    });

    test('a save without MANAGE_GUILD is refused locally', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(
        repository: repository,
        permissions: DiscordPermissions.banMembers,
      );
      final patch = GuildOverviewPatch()..name = 'x';
      expect(await controller.saveOverview(patch), isFalse);
      expect(repository.calls, isEmpty);
    });

    test('a failed save is reported without losing the section', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.overview);
      repository.failNext = true;
      final patch = GuildOverviewPatch()..name = 'Renamed';
      expect(await controller.saveOverview(patch), isFalse);
      expect(controller.actionError, isNotNull);
      expect(controller.overview!.name, 'The Forge');
    });
  });

  _structureCases();

  group('bans', () {
    test('drops members the moderator does not outrank', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.banMembers(
        const BanRequest(
          userIds: [lowMemberId, highMemberId],
          deletion: BanMessageDeletion.lastDay,
          reason: 'raid',
        ),
      );
      expect(repository.bannedRequest!.userIds, [lowMemberId]);
      expect(repository.bannedRequest!.deletion, BanMessageDeletion.lastDay);
      expect(repository.bannedRequest!.reason, 'raid');
    });

    test('a selection of nobody bannable sends nothing', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      expect(
        await controller.banMembers(const BanRequest(userIds: [highMemberId])),
        isFalse,
      );
      expect(repository.calls, isEmpty);
    });

    test('BAN_MEMBERS is required', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(
        repository: repository,
        permissions: DiscordPermissions.manageGuild,
      );
      expect(
        await controller.banMembers(const BanRequest(userIds: [lowMemberId])),
        isFalse,
      );
      expect(await controller.unbanMember(lowMemberId), isFalse);
      expect(repository.calls, isEmpty);
    });

    test('a ban invalidates the list rather than patching it', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.bans);
      expect(controller.bans, hasLength(1));
      await controller.banMembers(const BanRequest(userIds: [lowMemberId]));
      repository.calls.clear();
      await controller.load(GuildSettingsSection.bans);
      expect(repository.calls, contains('loadBans'));
    });

    test('an unban removes the row', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.bans);
      expect(await controller.unbanMember(bannedUserId), isTrue);
      expect(controller.bans, isEmpty);
    });

    test('a kick needs both the bit and the hierarchy', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      expect(await controller.kickMember(highMemberId), isFalse);
      expect(await controller.kickMember(lowMemberId), isTrue);
      expect(repository.calls, contains('kickMember'));
    });

    test('searching replaces the list and a blank query restores it', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.searchBans('raider');
      expect(repository.calls, contains('searchBans'));
      expect(controller.bans, hasLength(1));
      repository.calls.clear();
      await controller.searchBans('   ');
      expect(repository.calls, contains('loadBans'));
    });

    test('a failed search is surfaced on the section', () async {
      final repository = FakeGuildManagementRepository()..failNext = true;
      final controller = _controller(repository: repository);
      await controller.searchBans('raider');
      expect(controller.errorFor(GuildSettingsSection.bans), isNotNull);
    });

    test('searching without BAN_MEMBERS does nothing', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(
        repository: repository,
        permissions: DiscordPermissions.manageGuild,
      );
      await controller.searchBans('raider');
      expect(repository.calls, isEmpty);
    });
  });

  group('invites', () {
    test('creating needs CREATE_INSTANT_INVITE', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(
        repository: repository,
        permissions: DiscordPermissions.manageGuild,
      );
      expect(
        await controller.createInvite(channelId: '222222222222222222'),
        isNull,
      );
      expect(repository.calls, isEmpty);
    });

    test('creating prepends the new invite', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.invites);
      expect(controller.invites, hasLength(1));
      final created = await controller.createInvite(
        channelId: '222222222222222222',
      );
      expect(created, isNotNull);
      expect(controller.invites.first.code, 'fresh');
    });

    test('revoking needs MANAGE_GUILD and removes the row', () async {
      final repository = FakeGuildManagementRepository();
      final permitted = _controller(repository: repository);
      await permitted.openSection(GuildSettingsSection.invites);
      expect(await permitted.revokeInvite('forge'), isTrue);
      expect(permitted.invites, isEmpty);

      final unprivileged = _controller(
        repository: repository,
        permissions: DiscordPermissions.banMembers,
      );
      expect(await unprivileged.revokeInvite('forge'), isFalse);
    });
  });

  group('audit log', () {
    test('merges the first page and reports whether more exist', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.auditLog);
      expect(controller.auditRecords, hasLength(1));
      expect(controller.auditRecords.single.count, 2);
      expect(controller.auditUserNames['123456789012345678'], 'Mira');
      expect(controller.hasOlderAuditEntries, isFalse);
    });

    test('filtering is exclusive between action and actor', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.filterAuditLog(
        action: AuditLogActionType.memberBanAdd,
        userId: '123456789012345678',
      );
      expect(controller.auditQuery.action, isNull);
      expect(controller.auditQuery.userId, '123456789012345678');
      await controller.filterAuditLog(action: AuditLogActionType.memberBanAdd);
      expect(controller.auditQuery.action, AuditLogActionType.memberBanAdd);
      expect(controller.auditQuery.userId, isNull);
    });

    test('a failed filter leaves the section retryable', () async {
      final repository = FakeGuildManagementRepository()..failNext = true;
      final controller = _controller(repository: repository);
      await controller.filterAuditLog(action: AuditLogActionType.roleCreate);
      expect(controller.errorFor(GuildSettingsSection.auditLog), isNotNull);
      expect(controller.isLoading(GuildSettingsSection.auditLog), isFalse);
    });

    test('paging appends and keeps the filter', () async {
      final repository = FakeGuildManagementRepository()..fullAuditPage = true;
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.auditLog);
      expect(controller.hasOlderAuditEntries, isTrue);
      final firstCount = controller.auditRecords.length;
      await controller.loadMoreAuditEntries();
      expect(controller.auditRecords.length, greaterThan(firstCount));
      expect(repository.lastAuditQuery!.before, isNotNull);
    });

    test('paging stops when there is nothing older', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.auditLog);
      repository.calls.clear();
      await controller.loadMoreAuditEntries();
      expect(repository.calls, isEmpty);
    });

    test('a failed page leaves the records intact', () async {
      final repository = FakeGuildManagementRepository()..fullAuditPage = true;
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.auditLog);
      final before = controller.auditRecords.length;
      repository.failNext = true;
      await controller.loadMoreAuditEntries();
      expect(controller.auditRecords, hasLength(before));
      expect(controller.errorFor(GuildSettingsSection.auditLog), isNotNull);
    });

    test('VIEW_AUDIT_LOG is required for both filtering and paging', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(
        repository: repository,
        permissions: DiscordPermissions.manageGuild,
      );
      await controller.filterAuditLog(action: AuditLogActionType.roleCreate);
      await controller.loadMoreAuditEntries();
      expect(repository.calls, isEmpty);
    });
  });

  test('a permission change while the window is open is honoured', () {
    final controller = _controller();
    expect(controller.availableSections, isNotEmpty);
    controller.capabilities = WorkspacePermissions(
      guildWorkspace(moderatorPermissions: DiscordPermissions.viewChannel),
      memberId: moderatorId,
    ).administrationOf(guildId);
    expect(controller.availableSections, isEmpty);
  });

  test('disposing stops further notifications', () {
    final controller = _controller();
    var notifications = 0;
    controller
      ..addListener(() => notifications++)
      ..dispose();
    controller.capabilities = WorkspacePermissions(
      guildWorkspace(),
      memberId: moderatorId,
    ).administrationOf(guildId);
    expect(notifications, 0);
  });
}

GuildSettingsController _controller({
  GuildManagementRepository? repository,
  BigInt? permissions,
}) => GuildSettingsController(
  repository ?? FakeGuildManagementRepository(),
  WorkspacePermissions(
    guildWorkspace(
      moderatorPermissions: permissions ?? allModerationPermissions,
    ),
    memberId: moderatorId,
  ).administrationOf(guildId),
  guildId: guildId,
);
