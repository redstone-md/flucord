import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a private channel is built and read: overwrites deny @everyone, roles
/// and members grant back in, and the sidebar lists exactly who was let in.
void main() {
  const guildId = '111111111111111111';
  const memberId = '123456789012345678';
  const otherMemberId = '234567890123456789';
  const staffRoleId = '222222222222222222';
  const channelBasename = 'channel';

  DiscordPermissionOverwrite overwrite(
    String id, {
    BigInt? allow,
    BigInt? deny,
    PermissionOverwriteKind kind = PermissionOverwriteKind.role,
  }) => DiscordPermissionOverwrite(
    id: id,
    allow: allow ?? BigInt.zero,
    deny: deny ?? BigInt.zero,
    kind: kind,
  );

  ConversationChannel privateChannel({
    Map<String, DiscordPermissionOverwrite> overwrites = const {},
  }) => ConversationChannel(
    id: channelBasename,
    spaceId: guildId,
    name: 'staff-room',
    topic: '',
    kind: ChannelKind.text,
    permissionOverwrites: overwrites,
  );

  ChatWorkspace workspace(List<ConversationChannel> channels) => ChatWorkspace(
    spaces: const [
      CommunitySpace(
        id: guildId,
        name: 'The Forge',
        monogram: 'TF',
        colorValue: 0xff456b5a,
      ),
    ],
    channels: channels,
    members: [
      Member(
        id: memberId,
        displayName: 'Mira',
        initials: 'MI',
        role: 'Staff',
        presence: Presence.online,
        colorValue: 0xff456b5a,
        spaceIds: const {guildId},
        membershipsBySpace: const {
          guildId: GuildMembership(roleIds: ['member', staffRoleId]),
        },
      ),
      Member(
        id: otherMemberId,
        displayName: 'Ada',
        initials: 'AD',
        role: 'Member',
        presence: Presence.online,
        colorValue: 0xff456b5a,
        spaceIds: const {guildId},
        membershipsBySpace: const {
          guildId: GuildMembership(roleIds: ['member']),
        },
      ),
    ],
    roles: [
      CommunityRole(
        id: guildId,
        spaceId: guildId,
        name: '@everyone',
        position: 0,
        permissions: DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.sendMessages,
          DiscordPermissions.readMessageHistory,
        ]),
      ),
      const CommunityRole(
        id: 'member',
        spaceId: guildId,
        name: 'Member',
        position: 1,
      ),
      const CommunityRole(
        id: staffRoleId,
        spaceId: guildId,
        name: 'Staff',
        position: 5,
      ),
    ],
    messages: const [],
    currentMemberId: memberId,
  );

  test(
    'a private channel hides from members and appears for the permitted',
    () {
      final channel = privateChannel(
        overwrites: {
          // The classic private channel: @everyone denied, one role allowed.
          guildId: overwrite(guildId, deny: DiscordPermissions.viewChannel),
          staffRoleId: overwrite(
            staffRoleId,
            allow: DiscordPermissions.viewChannel,
          ),
        },
      );
      final space = workspace([channel]);

      final permitted = WorkspacePermissions(space, memberId: memberId);
      expect(permitted.visibleChannelsFor(guildId), [channel]);

      final outsider = WorkspacePermissions(space, memberId: otherMemberId);
      expect(outsider.visibleChannelsFor(guildId), isEmpty);
    },
  );

  test('a member overwrite overrides the role answer for that member only', () {
    final channel = privateChannel(
      overwrites: {
        guildId: overwrite(guildId, deny: DiscordPermissions.viewChannel),
        // A member let in by name, not by role.
        otherMemberId: overwrite(
          otherMemberId,
          allow: DiscordPermissions.viewChannel,
          kind: PermissionOverwriteKind.member,
        ),
      },
    );
    final space = workspace([channel]);

    // The named member sees it, the role-holding one does not.
    expect(
      WorkspacePermissions(
        space,
        memberId: otherMemberId,
      ).visibleChannelsFor(guildId),
      [channel],
    );
    expect(
      WorkspacePermissions(
        space,
        memberId: memberId,
      ).visibleChannelsFor(guildId),
      isEmpty,
    );
  });

  test('a private channel denied to a member by name is private to them', () {
    final channel = privateChannel(
      overwrites: {
        otherMemberId: overwrite(
          otherMemberId,
          deny: DiscordPermissions.viewChannel,
          kind: PermissionOverwriteKind.member,
        ),
      },
    );
    final space = workspace([channel]);

    expect(
      WorkspacePermissions(
        space,
        memberId: otherMemberId,
      ).visibleChannelsFor(guildId),
      isEmpty,
    );
    expect(
      WorkspacePermissions(
        space,
        memberId: memberId,
      ).visibleChannelsFor(guildId),
      [channel],
    );
  });

  test('an unknown member record reads the fail-open answer', () {
    final channel = privateChannel(
      overwrites: {
        guildId: overwrite(guildId, deny: DiscordPermissions.viewChannel),
      },
    );
    final space = workspace([channel]);

    // The workspace permission contract resolves a member it holds no
    // record for to full permissions, so a transport that never carried
    // member records still lists its channels. A live workspace always
    // carries the current member's own record, which is what the hiding
    // above runs on.
    expect(
      WorkspacePermissions(
        space,
        memberId: '987654321098765432',
      ).visibleChannelsFor(guildId),
      [channel],
    );
  });

  test('an overwrite editor round trip keeps the masks and the kinds', () {
    final channel = privateChannel(
      overwrites: {
        guildId: overwrite(
          guildId,
          allow: DiscordPermissions.sendMessages,
          deny: DiscordPermissions.viewChannel,
        ),
        staffRoleId: overwrite(
          staffRoleId,
          allow: DiscordPermissions.viewChannel,
          deny: DiscordPermissions.sendMessages,
        ),
        otherMemberId: overwrite(
          otherMemberId,
          allow: DiscordPermissions.viewChannel,
          kind: PermissionOverwriteKind.member,
        ),
      },
    );
    final space = workspace([channel]);
    final permissions = WorkspacePermissions(space, memberId: memberId);

    // The member holds both roles, so the role denies union first and the
    // allows after: view survives, send does not.
    final inChannel = permissions.inChannel(channel);
    expect(
      DiscordPermissions.hasAll(inChannel, DiscordPermissions.viewChannel),
      isTrue,
    );
    expect(
      DiscordPermissions.hasAll(inChannel, DiscordPermissions.sendMessages),
      isFalse,
    );
    // The member overwrite lets Ada back in untouched by the role fight.
    final ada = WorkspacePermissions(space, memberId: otherMemberId);
    expect(
      DiscordPermissions.hasAll(
        ada.inChannel(channel),
        DiscordPermissions.viewChannel,
      ),
      isTrue,
    );
  });
}
