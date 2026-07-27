import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';

void main() {
  test('a guild with no permission data answers unknown, not permitted', () {
    // Deliberately the opposite of the channel-level fallback: a sidebar that
    // fails open still only lists channels, whereas a settings window that
    // failed open would offer to delete roles.
    final permissions = WorkspacePermissions(
      _workspace(roles: const [], memberRoleIds: const []),
    );
    expect(permissions.inSpace('111111111111111111'), isNull);
    expect(
      permissions.canInSpace(
        DiscordPermissions.manageGuild,
        '111111111111111111',
      ),
      isFalse,
    );
    final capabilities = permissions.administrationOf('111111111111111111');
    expect(capabilities.hasAnySurface, isFalse);
    expect(capabilities.highestRolePosition, isNull);
    expect(capabilities.outranks('222222222222222222'), isFalse);
  });

  test('a guild this workspace does not hold answers unknown', () {
    final permissions = WorkspacePermissions(_workspace());
    expect(permissions.inSpace('222222222222222222'), isNull);
  });

  test('an unknown member record answers unknown', () {
    final permissions = WorkspacePermissions(
      _workspace(),
      memberId: '987654321098765432',
    );
    expect(permissions.inSpace('111111111111111111'), isNull);
  });

  test('each surface is gated on its own bit', () {
    final capabilities = _capabilities(
      moderatorPermissions: DiscordPermissions.combine([
        DiscordPermissions.viewChannel,
        DiscordPermissions.banMembers,
        DiscordPermissions.viewAuditLog,
      ]),
    );
    expect(capabilities.canBanMembers, isTrue);
    expect(capabilities.canViewAuditLog, isTrue);
    expect(capabilities.canManageGuild, isFalse);
    expect(capabilities.canManageRoles, isFalse);
    expect(capabilities.canManageChannels, isFalse);
    expect(capabilities.canKickMembers, isFalse);
    expect(capabilities.canCreateInvite, isFalse);
    expect(capabilities.hasAnySurface, isTrue);
  });

  test('a member with nothing sees no surface at all', () {
    final capabilities = _capabilities(
      moderatorPermissions: DiscordPermissions.viewChannel,
    );
    expect(capabilities.hasAnySurface, isFalse);
    expect(capabilities.highestRolePosition, 5);
  });

  group('role hierarchy', () {
    test('a role at or above the actor\'s highest cannot be edited', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.manageRoles,
      );
      expect(capabilities.canEditRole(_role('member', 1)), isTrue);
      expect(capabilities.canEditRole(_role('moderator', 5)), isFalse);
      expect(capabilities.canEditRole(_role('admin', 9)), isFalse);
    });

    test('a role in another guild is never editable here', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.manageRoles,
      );
      expect(
        capabilities.canEditRole(
          const CommunityRole(
            id: 'other',
            spaceId: '222222222222222222',
            name: 'other',
            position: 1,
          ),
        ),
        isFalse,
      );
    });

    test('MANAGE_ROLES alone is not enough', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.viewChannel,
      );
      expect(capabilities.canEditRole(_role('member', 1)), isFalse);
    });

    test('the owner is above every role', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.none,
        ownerId: '123456789012345678',
      );
      expect(capabilities.isOwner, isTrue);
      expect(capabilities.canEditRole(_role('admin', 9)), isTrue);
      expect(capabilities.outranks('987654321098765432'), isTrue);
    });

    test('@everyone can never be deleted', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.manageRoles,
        ownerId: '123456789012345678',
      );
      expect(
        capabilities.canDeleteRole(_role('111111111111111111', 0)),
        isFalse,
      );
      expect(capabilities.canDeleteRole(_role('member', 1)), isTrue);
    });
  });

  group('outranking', () {
    test('nobody outranks themselves', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.banMembers,
      );
      expect(capabilities.outranks('123456789012345678'), isFalse);
      expect(capabilities.canBan('123456789012345678'), isFalse);
    });

    test('nobody outranks the owner', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.banMembers,
        ownerId: '987654321098765432',
      );
      expect(capabilities.outranks('987654321098765432'), isFalse);
    });

    test('a lower member can be banned and kicked', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.combine([
          DiscordPermissions.banMembers,
          DiscordPermissions.kickMembers,
        ]),
      );
      expect(capabilities.canBan('234567890123456789'), isTrue);
      expect(capabilities.canKick('234567890123456789'), isTrue);
    });

    test('a member holding a higher role cannot be banned', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.banMembers,
      );
      expect(capabilities.canBan('987654321098765432'), isFalse);
    });

    test('a member this client has no record for outranks nobody', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.banMembers,
      );
      expect(capabilities.outranks('333333333333333333'), isTrue);
    });

    test('BAN_MEMBERS is still required', () {
      final capabilities = _capabilities(
        moderatorPermissions: DiscordPermissions.viewChannel,
      );
      expect(capabilities.canBan('234567890123456789'), isFalse);
      expect(capabilities.canKick('234567890123456789'), isFalse);
    });
  });
}

const _guildId = '111111111111111111';
const _moderatorId = '123456789012345678';

CommunityRole _role(String id, int position) =>
    CommunityRole(id: id, spaceId: _guildId, name: id, position: position);

GuildAdminCapabilities _capabilities({
  required BigInt moderatorPermissions,
  String? ownerId,
}) => WorkspacePermissions(
  _workspace(
    ownerId: ownerId,
    roles: [
      CommunityRole(
        id: _guildId,
        spaceId: _guildId,
        name: '@everyone',
        position: 0,
        permissions: DiscordPermissions.viewChannel,
      ),
      const CommunityRole(
        id: 'member',
        spaceId: _guildId,
        name: 'member',
        position: 1,
      ),
      CommunityRole(
        id: 'moderator',
        spaceId: _guildId,
        name: 'moderator',
        position: 5,
        permissions: moderatorPermissions,
      ),
      CommunityRole(
        id: 'admin',
        spaceId: _guildId,
        name: 'admin',
        position: 9,
        permissions: DiscordPermissions.viewChannel,
      ),
      const CommunityRole(
        id: 'elsewhere',
        spaceId: '222222222222222222',
        name: 'elsewhere',
        position: 90,
      ),
    ],
  ),
  memberId: _moderatorId,
).administrationOf(_guildId);

ChatWorkspace _workspace({
  String? ownerId,
  List<CommunityRole>? roles,
  List<String> memberRoleIds = const ['moderator'],
}) => ChatWorkspace(
  spaces: [
    CommunitySpace(
      id: _guildId,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
      ownerId: ownerId,
    ),
  ],
  channels: const [],
  members: [
    Member(
      id: _moderatorId,
      displayName: 'Mira',
      initials: 'MI',
      role: 'moderator',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: const {_guildId},
      membershipsBySpace: {_guildId: GuildMembership(roleIds: memberRoleIds)},
    ),
    const Member(
      id: '987654321098765432',
      displayName: 'Kai',
      initials: 'KA',
      role: 'admin',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {_guildId},
      membershipsBySpace: {
        _guildId: GuildMembership(roleIds: ['admin']),
      },
    ),
    const Member(
      id: '234567890123456789',
      displayName: 'Ada',
      initials: 'AD',
      role: 'member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {_guildId},
      membershipsBySpace: {
        _guildId: GuildMembership(roleIds: ['member']),
      },
    ),
  ],
  messages: const [],
  currentMemberId: _moderatorId,
  roles: roles ?? const [],
);
