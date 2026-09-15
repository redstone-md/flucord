import 'dart:io';

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

    test('reads a channel editor payload into the channel model', () {
      final voice = DiscordMapper().channel(const {
        'id': 'channel-1',
        'name': 'workbench',
        'type': 2,
        'rate_limit_per_user': 30,
        'nsfw': true,
        'bitrate': 128000,
        'user_limit': 25,
        'rtc_region': 'rotterdam',
      }, 'guild-1')!;
      expect(voice.rateLimitPerUser, 30);
      expect(voice.isAgeGated, isTrue);
      expect(voice.bitrate, 128000);
      expect(voice.userLimit, 25);
      expect(voice.rtcRegion, 'rotterdam');

      // Automatic is spelled both null and the literal string "auto".
      final auto = DiscordMapper().channel(const {
        'id': 'channel-2',
        'name': 'room',
        'type': 2,
      }, 'guild-1')!;
      expect(auto.rtcRegion, isNull);
      final autoWord = DiscordMapper().channel(const {
        'id': 'channel-3',
        'name': 'room',
        'type': 2,
        'rtc_region': 'auto',
      }, 'guild-1')!;
      expect(autoWord.rtcRegion, isNull);

      final text = DiscordMapper().channel(const {
        'id': 'channel-4',
        'name': 'general',
        'type': 0,
      }, 'guild-1')!;
      expect(text.rateLimitPerUser, 0);
      expect(text.isAgeGated, isFalse);
      expect(text.rtcRegion, isNull);
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
            rateLimitPerUser: 30,
            isAgeGated: true,
            bitrate: 128000,
            userLimit: 25,
            rtcRegion: 'rotterdam',
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
      final restoredChannel = restored.channelById('channel-1');
      expect(restoredChannel.rateLimitPerUser, 30);
      expect(restoredChannel.isAgeGated, isTrue);
      expect(restoredChannel.bitrate, 128000);
      expect(restoredChannel.userLimit, 25);
      expect(restoredChannel.rtcRegion, 'rotterdam');
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

    test('a v21 cache upgrades its channels and reads them', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flucord-channel-config-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}cache.sqlite3';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 21,
          onCreate: (database, _) => _createV21ChannelTables(database),
        ),
      );
      await legacy.insert('metadata', {
        'key': 'current_member_id',
        'value': 'member-1',
      });
      await legacy.insert('spaces', {
        'id': 'guild-1',
        'name': 'The Forge',
        'monogram': 'TF',
        'color_value': 0xff456b5a,
        'kind': 0,
        'sort_index': 0,
      });
      // A channel row written before this version knows nothing about the
      // editor fields, which is exactly what the upgrade has to survive.
      await legacy.insert('channels', {
        'id': 'channel-1',
        'space_id': 'guild-1',
        'name': 'workbench',
        'topic': '',
        'kind': 1,
        'position': 0,
        'unread': 0,
        'mention_count': 0,
        'is_thread': 0,
        'is_archived': 0,
        'is_locked': 0,
        'available_tags_json': '[]',
        'applied_tag_ids_json': '[]',
        'sort_index': 0,
      });
      await legacy.close();

      final cache = await SqliteChatCache.openAt(
        path,
        factory: databaseFactoryFfi,
      );
      addTearDown(cache.close);
      final restored = await cache.readWorkspace();
      expect(restored, isNotNull);
      final voice = restored!.channelById('channel-1');
      expect(voice.name, 'workbench');
      expect(voice.rateLimitPerUser, 0);
      expect(voice.isAgeGated, isFalse);
      expect(voice.bitrate, isNull);
      expect(voice.userLimit, isNull);
      expect(voice.rtcRegion, isNull);
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

/// The channel, metadata and spaces tables as version 21 shaped them, minus
/// every column the channel-config upgrade adds.
Future<void> _createV21ChannelTables(Database database) async {
  await database.execute('''
    CREATE TABLE metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE spaces (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      monogram TEXT NOT NULL,
      color_value INTEGER NOT NULL,
      icon_url TEXT,
      kind INTEGER NOT NULL,
      owner_id TEXT,
      requires_mfa INTEGER NOT NULL DEFAULT 0,
      sort_index INTEGER NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE channels (
      id TEXT PRIMARY KEY,
      space_id TEXT NOT NULL,
      name TEXT NOT NULL,
      topic TEXT NOT NULL,
      kind INTEGER NOT NULL,
      position INTEGER NOT NULL,
      unread INTEGER NOT NULL,
      mention_count INTEGER NOT NULL,
      first_unread_message_id TEXT,
      last_message_id TEXT,
      parent_id TEXT,
      is_thread INTEGER NOT NULL,
      is_archived INTEGER NOT NULL,
      is_locked INTEGER NOT NULL,
      archive_timestamp TEXT,
      auto_archive_duration INTEGER,
      available_tags_json TEXT NOT NULL,
      applied_tag_ids_json TEXT NOT NULL,
      default_auto_archive_duration INTEGER,
      default_sort_order INTEGER,
      default_forum_layout INTEGER,
      recipient_id TEXT,
      permission_overwrites_json TEXT,
      sort_index INTEGER NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      space_id TEXT NOT NULL,
      name TEXT NOT NULL,
      position INTEGER NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE roles (
      id TEXT PRIMARY KEY,
      space_id TEXT NOT NULL,
      name TEXT NOT NULL,
      position INTEGER NOT NULL,
      color_value INTEGER,
      permissions TEXT
    )
  ''');
  await database.execute('''
    CREATE TABLE members (
      id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      initials TEXT NOT NULL,
      role TEXT NOT NULL,
      presence INTEGER NOT NULL,
      color_value INTEGER,
      avatar_url TEXT,
      space_ids_json TEXT NOT NULL,
      roles_by_space_json TEXT NOT NULL,
      avatar_urls_by_space_json TEXT NOT NULL,
      memberships_json TEXT
    )
  ''');
  await database.execute('''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      channel_id TEXT NOT NULL,
      author_id TEXT NOT NULL,
      body TEXT NOT NULL,
      message_type INTEGER NOT NULL,
      reference_message_id TEXT,
      reference_channel_id TEXT,
      reference_guild_id TEXT,
      reference_type INTEGER NOT NULL,
      snapshots_json TEXT NOT NULL,
      flags INTEGER NOT NULL,
      sent_at TEXT NOT NULL,
      is_edited INTEGER NOT NULL,
      attachments_json TEXT NOT NULL,
      reply_json TEXT,
      reactions_json TEXT NOT NULL,
      is_pinned INTEGER NOT NULL,
      embeds_json TEXT NOT NULL,
      mentions_current_member INTEGER NOT NULL,
      poll_json TEXT,
      stickers_json TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE emojis (
      id TEXT PRIMARY KEY,
      space_id TEXT NOT NULL,
      name TEXT NOT NULL,
      image_url TEXT,
      animated INTEGER NOT NULL,
      available INTEGER NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE guild_stickers (
      id TEXT PRIMARY KEY,
      space_id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      asset_url TEXT,
      sort_index INTEGER NOT NULL
    )
  ''');
}
