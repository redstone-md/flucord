import 'package:flucord/src/data/discord/discord_desktop_bootstrap.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('mapper', () {
    test('keeps the role permission bits the wire carried', () {
      final mapper = DiscordMapper();

      final withBits = mapper.role(const {
        'id': 'role-1',
        'name': 'Staff',
        'position': 3,
        'permissions': '2251799813685248',
      }, 'guild-1');
      final without = mapper.role(const {'id': 'guild-1'}, 'guild-1');

      expect(withBits.permissions, DiscordPermissions.pinMessages);
      expect(withBits.isEveryone, isFalse);
      expect(without.permissions, isNull);
      expect(without.isEveryone, isTrue);
    });

    test('reads channel overwrites into a map keyed by id', () {
      final channel = DiscordMapper().channel(const {
        'id': 'channel-1',
        'name': 'staff',
        'type': 0,
        'permission_overwrites': [
          {'id': 'guild-1', 'type': 0, 'allow': '0', 'deny': '1024'},
          {'id': 'member-1', 'type': 1, 'allow': '1024', 'deny': '0'},
        ],
      }, 'guild-1')!;

      expect(channel.permissionOverwrites, hasLength(2));
      expect(
        channel.permissionOverwrites['guild-1']!.denies(
          DiscordPermissions.viewChannel,
        ),
        isTrue,
      );
      expect(
        channel.permissionOverwrites['member-1']!.kind,
        PermissionOverwriteKind.member,
      );
      expect(
        DiscordMapper().channel(const {
          'id': 'c',
          'name': 'c',
          'type': 0,
        }, 'guild-1')!.permissionOverwrites,
        isEmpty,
      );
    });

    test('reads the owner and two-factor level from either guild shape', () {
      final flat = DiscordMapper().workspace(
        currentUser: const {'id': 'member-1', 'username': 'Ada'},
        guilds: const [
          {
            'id': 'guild-1',
            'name': 'Flat',
            'owner_id': 'member-1',
            'mfa_level': 1,
          },
        ],
        channelsByGuild: const {
          'guild-1': [
            {'id': 'c1', 'name': 'general', 'type': 0},
          ],
        },
      );
      final split = DiscordMapper().workspace(
        currentUser: const {'id': 'member-1', 'username': 'Ada'},
        guilds: const [
          {
            'id': 'guild-2',
            'properties': {'owner_id': 'member-9', 'mfa_level': 0},
          },
        ],
        channelsByGuild: const {
          'guild-2': [
            {'id': 'c2', 'name': 'general', 'type': 0},
          ],
        },
      );

      expect(flat.spaceById('guild-1').ownerId, 'member-1');
      expect(flat.spaceById('guild-1').requiresMultiFactorAuth, isTrue);
      expect(split.spaceById('guild-2').ownerId, 'member-9');
      expect(split.spaceById('guild-2').requiresMultiFactorAuth, isFalse);
    });

    test('keeps the member fields the clamps depend on', () {
      final member = DiscordMapper().guildMember(
        const {
          'user': {'id': 'member-1', 'username': 'Ada'},
          'roles': ['role-1', 'role-2'],
          'flags': GuildMembership.guestFlag,
          'pending': true,
          'communication_disabled_until': '2026-07-26T12:00:00.000Z',
        },
        'guild-1',
        const [],
      );

      final membership = member.membershipIn('guild-1')!;
      expect(membership.roleIds, ['role-1', 'role-2']);
      expect(membership.isGuest, isTrue);
      expect(membership.isPending, isTrue);
      expect(membership.isTimedOutAt(DateTime.utc(2026, 7, 26, 11)), isTrue);
      expect(member.membershipIn('guild-2'), isNull);
    });

    test('a member payload without the optional fields is still a record', () {
      final membership = DiscordMapper().membership(const {});

      expect(membership.roleIds, isEmpty);
      expect(membership.flags, 0);
      expect(membership.isPending, isFalse);
      expect(membership.timeoutUntil, isNull);
    });

    test('merging members keeps memberships from every guild', () {
      final workspace = DiscordMapper().workspace(
        currentUser: const {'id': 'member-1', 'username': 'Ada'},
        guilds: const [
          {'id': 'guild-1', 'name': 'One'},
          {'id': 'guild-2', 'name': 'Two'},
        ],
        channelsByGuild: const {
          'guild-1': [
            {'id': 'c1', 'name': 'general', 'type': 0},
          ],
          'guild-2': [
            {'id': 'c2', 'name': 'general', 'type': 0},
          ],
        },
        membersByGuild: const {
          'guild-1': [
            {
              'user': {'id': 'member-1'},
              'roles': ['role-1'],
            },
          ],
          'guild-2': [
            {
              'user': {'id': 'member-1'},
              'roles': ['role-2'],
            },
          ],
        },
      );

      final member = workspace.memberById('member-1');
      expect(member.membershipIn('guild-1')!.roleIds, ['role-1']);
      expect(member.membershipIn('guild-2')!.roleIds, ['role-2']);
    });
  });

  group('desktop bootstrap', () {
    test('pairs merged_members positionally, counting unavailable guilds', () {
      final bootstrap = DiscordDesktopBootstrap();

      bootstrap.acceptReady(const {
        'user': {'id': '123456789012345678', 'username': 'Ada'},
        'users': [
          {'id': '123456789012345678', 'username': 'Ada'},
        ],
        'guilds': [
          {'id': 'guild-unavailable', 'unavailable': true},
          {
            'id': 'guild-1',
            'roles': [
              {'id': 'guild-1', 'permissions': '1024'},
            ],
            'channels': [
              {'id': 'c1', 'type': 0, 'name': 'general'},
            ],
          },
        ],
        'merged_members': [
          <Object?>[],
          [
            {
              'user_id': '123456789012345678',
              'roles': ['role-1'],
            },
          ],
        ],
      });
      final snapshot = bootstrap.snapshot()!;

      expect(snapshot.rolesByGuild['guild-1']!.single['permissions'], '1024');
      expect(snapshot.membersByGuild.containsKey('guild-unavailable'), isFalse);
      final member = snapshot.membersByGuild['guild-1']!.single;
      expect(member['roles'], ['role-1']);
      expect((member['user']! as Map)['username'], 'Ada');
      expect(member.containsKey('user_id'), isFalse);
    });

    test('survives a short, null, or unresolvable merged_members array', () {
      final bootstrap = DiscordDesktopBootstrap();

      bootstrap.acceptReady(const {
        'user': {'id': '123456789012345678'},
        'guilds': [
          {
            'id': 'guild-1',
            'channels': [
              {'id': 'c1', 'type': 0, 'name': 'general'},
            ],
          },
          {
            'id': 'guild-2',
            'channels': [
              {'id': 'c2', 'type': 0, 'name': 'general'},
            ],
          },
        ],
        'merged_members': [
          null,
          [
            {'user_id': '234567890123456789'},
          ],
        ],
      });
      final snapshot = bootstrap.snapshot()!;

      expect(snapshot.membersByGuild, isEmpty);
      expect(bootstrap.users.unresolvedIds, contains('234567890123456789'));
    });

    test('takes the members a GUILD_CREATE carries inline', () {
      final bootstrap = DiscordDesktopBootstrap();

      bootstrap.acceptReady(const {
        'user': {'id': '123456789012345678'},
        'guilds': <Object?>[],
      });
      bootstrap.acceptGuild(const {
        'id': 'guild-1',
        'roles': [
          {'id': 'guild-1', 'permissions': '2048'},
        ],
        'channels': [
          {'id': 'c1', 'type': 0, 'name': 'general'},
        ],
        'members': [
          {
            'user': {'id': '234567890123456789'},
            'roles': ['role-1'],
          },
        ],
      });
      final snapshot = bootstrap.snapshot()!;

      expect(snapshot.membersByGuild['guild-1'], hasLength(1));
      expect(snapshot.rolesByGuild['guild-1'], hasLength(1));
      expect(
        () => snapshot.rolesByGuild['guild-1']!.add(const {}),
        throwsUnsupportedError,
      );

      bootstrap.reset();
      expect(bootstrap.snapshot(), isNull);
    });

    test('a replayed READY drops the previous session roles and members', () {
      final bootstrap = DiscordDesktopBootstrap();
      const ready = {
        'user': {'id': '123456789012345678'},
        'guilds': [
          {
            'id': 'guild-1',
            'roles': [
              {'id': 'guild-1', 'permissions': '1024'},
            ],
          },
        ],
        'merged_members': [
          [
            {
              'user': {'id': '123456789012345678'},
            },
          ],
        ],
      };

      bootstrap.acceptReady(ready);
      bootstrap.acceptReady(const {
        'user': {'id': '123456789012345678'},
        'guilds': <Object?>[],
      });

      final snapshot = bootstrap.snapshot()!;
      expect(snapshot.rolesByGuild, isEmpty);
      expect(snapshot.membersByGuild, isEmpty);
    });
  });

  group('cache', () {
    test('round-trips everything a permission decision reads', () async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(cache.close);
      final workspace = ChatWorkspace(
        spaces: const [
          CommunitySpace(
            id: 'guild-1',
            name: 'The Forge',
            monogram: 'TF',
            colorValue: 0xff456b5a,
            ownerId: 'member-9',
            requiresMultiFactorAuth: true,
          ),
        ],
        channels: [
          ConversationChannel(
            id: 'channel-1',
            spaceId: 'guild-1',
            name: 'staff',
            topic: '',
            kind: ChannelKind.text,
            permissionOverwrites: {
              'guild-1': DiscordPermissionOverwrite(
                id: 'guild-1',
                allow: DiscordPermissions.pinMessages,
                deny: DiscordPermissions.viewChannel,
              ),
            },
          ),
        ],
        roles: [
          CommunityRole(
            id: 'guild-1',
            spaceId: 'guild-1',
            name: '@everyone',
            position: 0,
            permissions: DiscordPermissions.viewChannel,
          ),
          const CommunityRole(
            id: 'role-legacy',
            spaceId: 'guild-1',
            name: 'Legacy',
            position: 1,
          ),
        ],
        members: [
          Member(
            id: 'member-1',
            displayName: 'Ada',
            initials: 'A',
            role: 'Member',
            presence: Presence.online,
            colorValue: 0xff456b5a,
            spaceIds: const {'guild-1'},
            membershipsBySpace: {
              'guild-1': GuildMembership(
                roleIds: const ['role-legacy'],
                flags: 128,
                isPending: true,
                timeoutUntil: DateTime.utc(2026, 7, 26, 12),
              ),
            },
          ),
        ],
        messages: const [],
        currentMemberId: 'member-1',
      );

      await cache.writeWorkspace(workspace);
      final restored = (await cache.readWorkspace())!;

      expect(
        restored.roleOrNull('guild-1')!.permissions,
        DiscordPermissions.viewChannel,
      );
      expect(restored.roleOrNull('role-legacy')!.permissions, isNull);
      expect(restored.spaceById('guild-1').ownerId, 'member-9');
      expect(restored.spaceById('guild-1').requiresMultiFactorAuth, isTrue);
      final overwrite = restored
          .channelById('channel-1')
          .permissionOverwrites['guild-1']!;
      expect(overwrite.allow, DiscordPermissions.pinMessages);
      expect(overwrite.deny, DiscordPermissions.viewChannel);
      final membership = restored
          .memberById('member-1')
          .membershipIn('guild-1')!;
      expect(membership.roleIds, ['role-legacy']);
      expect(membership.isQuarantined, isTrue);
      expect(membership.isPending, isTrue);
      expect(membership.timeoutUntil, DateTime.utc(2026, 7, 26, 12));
      // The restored workspace answers the same question the live one did.
      expect(
        WorkspacePermissions(restored).visibleChannelsFor('guild-1'),
        isEmpty,
      );
    });

    test('a member row written before this version reads as unknown', () async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(cache.close);
      const member = Member(
        id: 'member-1',
        displayName: 'Ada',
        initials: 'A',
        role: 'Member',
        presence: Presence.online,
        colorValue: 0xff456b5a,
      );

      await cache.writeMember(member);
      final history = await cache.readChannelHistory('channel-1');

      expect(history.members, isEmpty);
      expect(member.membershipsBySpace, isEmpty);
    });
  });
}
