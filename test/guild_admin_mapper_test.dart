import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_guild_admin_mapper.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';
import 'package:flucord/src/domain/guild_management.dart';

void main() {
  group('guild overview', () {
    test('reads every field the settings window renders', () {
      final settings = DiscordGuildAdminMapper.guildOverview({
        'id': '111111111111111111',
        'name': 'The Forge',
        'icon': 'iconhash',
        'description': 'A workshop',
        'owner_id': '123456789012345678',
        'preferred_locale': 'en-GB',
        'afk_channel_id': '222222222222222222',
        'afk_timeout': 900,
        'system_channel_id': '333333333333333333',
        'system_channel_flags': 3,
        'verification_level': 2,
        'explicit_content_filter': 1,
        'default_message_notifications': 1,
        'mfa_level': 1,
        'premium_progress_bar_enabled': true,
        'features': ['COMMUNITY', 42, 'NEWS'],
      });
      expect(settings.id, '111111111111111111');
      expect(settings.name, 'The Forge');
      expect(settings.iconHash, 'iconhash');
      expect(settings.description, 'A workshop');
      expect(settings.ownerId, '123456789012345678');
      expect(settings.preferredLocale, 'en-GB');
      expect(settings.afkChannelId, '222222222222222222');
      expect(settings.afkTimeoutSeconds, 900);
      expect(settings.systemChannelId, '333333333333333333');
      expect(settings.systemChannelFlags, 3);
      expect(settings.verificationLevel, GuildVerificationLevel.medium);
      expect(
        settings.explicitContentFilter,
        GuildExplicitContentFilter.membersWithoutRoles,
      );
      expect(
        settings.defaultMessageNotifications,
        GuildNotificationLevel.onlyMentions,
      );
      expect(settings.mfaLevel, GuildMfaLevel.elevated);
      expect(settings.premiumProgressBarEnabled, isTrue);
      expect(settings.features, {'COMMUNITY', 'NEWS'});
    });

    test('a level this build has no name for stays null', () {
      final settings = DiscordGuildAdminMapper.guildOverview(const {
        'id': '111111111111111111',
        'name': 'The Forge',
        'verification_level': 97,
        'default_message_notifications': 'nonsense',
        'afk_timeout': '600',
      });
      expect(settings.verificationLevel, isNull);
      expect(settings.defaultMessageNotifications, isNull);
      expect(settings.afkTimeoutSeconds, 600);
      expect(settings.iconHash, isNull);
      expect(settings.features, isEmpty);
      expect(settings.premiumProgressBarEnabled, isFalse);
    });

    test('an empty payload still produces a record', () {
      final settings = DiscordGuildAdminMapper.guildOverview(const {});
      expect(settings.id, isEmpty);
      expect(settings.name, isEmpty);
      expect(settings.afkTimeoutSeconds, 300);
      expect(settings.systemChannelFlags, 0);
    });
  });

  group('roles', () {
    test('parses the decimal bitfield as an unsigned BigInt', () {
      final role = DiscordGuildAdminMapper.role(const {
        'id': '222222222222222222',
        'name': 'Moderator',
        'position': 4,
        'permissions': '9007199254740992',
        'color': 0x4c9b72,
        'hoist': true,
        'mentionable': true,
        'managed': false,
        'icon': 'roleicon',
        'unicode_emoji': '🔨',
      }, '111111111111111111');
      expect(role.permissions, BigInt.parse('9007199254740992'));
      expect(role.colorValue, 0x4c9b72);
      expect(role.hoist, isTrue);
      expect(role.mentionable, isTrue);
      expect(role.managed, isFalse);
      expect(role.iconHash, 'roleicon');
      expect(role.unicodeEmoji, '🔨');
      expect(role.isEveryone, isFalse);
    });

    test('a negative bitfield grants nothing', () {
      // A "-1" permission string once meant full administrator. It must read as
      // no permissions at all, never as every bit set.
      final role = DiscordGuildAdminMapper.role(const {
        'id': '111111111111111111',
        'permissions': '-1',
      }, '111111111111111111');
      expect(role.permissions, BigInt.zero);
      expect(role.isEveryone, isTrue);
      expect(role.name, isEmpty);
      expect(role.position, 0);
    });

    test('the new colours object wins over the legacy int', () {
      final role = DiscordGuildAdminMapper.role(const {
        'id': '222222222222222222',
        'color': 1,
        'colors': {'primary_color': 99, 'secondary_color': null},
      }, '111111111111111111');
      expect(role.colorValue, 99);
    });

    test('maps a whole list', () {
      final roles = DiscordGuildAdminMapper.roles(const [
        {'id': '222222222222222222', 'name': 'a', 'position': 2},
        {'id': '333333333333333333', 'name': 'b', 'position': 1},
      ], '111111111111111111');
      expect(roles.map((role) => role.name), ['a', 'b']);
      roles.sort(GuildRole.compareForDisplay);
      expect(roles.first.name, 'a');
    });

    test('ties are broken by id so the list never reshuffles', () {
      final left = DiscordGuildAdminMapper.role(const {
        'id': '222222222222222222',
        'position': 1,
      }, '111111111111111111');
      final right = DiscordGuildAdminMapper.role(const {
        'id': '333333333333333333',
        'position': 1,
      }, '111111111111111111');
      expect(GuildRole.compareForDisplay(left, right), lessThan(0));
    });
  });

  group('bans', () {
    test('reads the user record and the reason', () {
      final bans = DiscordGuildAdminMapper.bans(const [
        {
          'user': {
            'id': '123456789012345678',
            'username': 'raider',
            'global_name': 'Raider',
            'avatar': 'hash',
          },
          'reason': 'Spam',
        },
        {'reason': 'no user object'},
        {
          'user': {'username': 'no id'},
        },
      ]);
      expect(bans, hasLength(1));
      expect(bans.single.userId, '123456789012345678');
      expect(bans.single.displayName, 'Raider');
      expect(bans.single.avatarHash, 'hash');
      expect(bans.single.reason, 'Spam');
    });

    test('falls back to the username when there is no display name', () {
      final ban = DiscordGuildAdminMapper.ban(const {
        'user': {'id': '123456789012345678', 'username': 'raider'},
      });
      expect(ban!.displayName, 'raider');
      expect(ban.reason, isNull);
    });

    test('reads a bulk ban result', () {
      final result = DiscordGuildAdminMapper.bulkBanResult(const {
        'banned_users': ['123456789012345678', 42],
        'failed_users': ['222222222222222222'],
      });
      expect(result.bannedUserIds, ['123456789012345678']);
      expect(result.failedUserIds, ['222222222222222222']);
      expect(result.isCompleteSuccess, isFalse);
      expect(const BulkBanResult().isCompleteSuccess, isTrue);
    });
  });

  group('invites', () {
    test('reads the fields the invites page shows', () {
      final invites = DiscordGuildAdminMapper.invites(const [
        {
          'code': 'forge',
          'channel': {'id': '222222222222222222', 'name': 'general'},
          'inviter': {'id': '123456789012345678', 'global_name': 'Mira'},
          'uses': 3,
          'max_uses': 10,
          'max_age': 3600,
          'temporary': true,
          'created_at': '2026-07-27T10:00:00+00:00',
        },
        {'no': 'code'},
      ]);
      expect(invites, hasLength(1));
      final invite = invites.single;
      expect(invite.channelId, '222222222222222222');
      expect(invite.channelName, 'general');
      expect(invite.inviterId, '123456789012345678');
      expect(invite.inviterName, 'Mira');
      expect(invite.uses, 3);
      expect(invite.maxUses, 10);
      expect(invite.temporary, isTrue);
      expect(invite.neverExpires, isFalse);
      expect(invite.hasUnlimitedUses, isFalse);
      expect(invite.url, 'https://discord.gg/forge');
      expect(invite.expiresAt, DateTime.parse('2026-07-27T11:00:00+00:00'));
      expect(invite.isExpiredAt(DateTime.utc(2026, 7, 27, 12)), isTrue);
      expect(invite.isExpiredAt(DateTime.utc(2026, 7, 27, 10, 30)), isFalse);
    });

    test('zero means unlimited, not missing', () {
      final invite = DiscordGuildAdminMapper.invite(const {
        'code': 'forever',
        'channel_id': '222222222222222222',
        'inviter': 'not an object',
      });
      expect(invite!.neverExpires, isTrue);
      expect(invite.hasUnlimitedUses, isTrue);
      expect(invite.expiresAt, isNull);
      expect(invite.isExpiredAt(DateTime.utc(2030)), isFalse);
      expect(invite.channelId, '222222222222222222');
      expect(invite.inviterName, isNull);
    });

    test('falls back to the username for the inviter', () {
      final invite = DiscordGuildAdminMapper.invite(const {
        'code': 'x',
        'inviter': {'id': '1', 'username': 'mira'},
      });
      expect(invite!.inviterName, 'mira');
    });
  });

  group('audit log', () {
    test('derives the timestamp from the snowflake', () {
      final page = DiscordGuildAdminMapper.auditLog(const {
        'audit_log_entries': [
          {
            'id': '987654321098765432',
            'action_type': 22,
            'target_id': '123456789012345678',
            'user_id': '111111111111111111',
            'reason': 'Raid',
            'changes': [
              {'key': 'nick', 'old_value': 'a', 'new_value': 'b'},
              {'no': 'key'},
              'not a map',
            ],
            'options': {'delete_member_days': 1},
          },
          {'id': '111111111111111111', 'action_type': 9999},
          {'action_type': 22},
          'not a map',
        ],
        'users': [
          {'id': '111111111111111111', 'global_name': 'Mira'},
          {'id': '222222222222222222', 'username': 'kai'},
          {'no': 'id'},
          {'id': '333333333333333333'},
        ],
        'threads': [
          {'id': '234567890123456789', 'name': 'incident'},
        ],
      });
      expect(page.entries, hasLength(1));
      final entry = page.entries.single;
      expect(entry.action, AuditLogActionType.memberBanAdd);
      expect(entry.targetType, AuditLogTargetType.user);
      expect(entry.actionClass, AuditLogActionClass.create);
      expect(entry.reason, 'Raid');
      expect(entry.changes, hasLength(1));
      expect(entry.changes.single.key, 'nick');
      expect(entry.options, {'delete_member_days': 1});
      expect(
        entry.timestamp.millisecondsSinceEpoch,
        greaterThan(DateTime.utc(2020).millisecondsSinceEpoch),
      );
      expect(page.userNames['111111111111111111'], 'Mira');
      expect(page.userNames['222222222222222222'], 'kai');
      expect(page.userNames['333333333333333333'], '333333333333333333');
      expect(page.channelNames['234567890123456789'], 'incident');
    });

    test('an entry with no options carries an empty map', () {
      final entry = DiscordGuildAdminMapper.auditLogEntry(const {
        'id': '987654321098765432',
        'action_type': 10,
        'options': 'not a map',
      });
      expect(entry!.options, isEmpty);
      expect(entry.changes, isEmpty);
      expect(entry.userId, isNull);
    });

    test('a response with no entries is an empty page', () {
      final page = DiscordGuildAdminMapper.auditLog(const {});
      expect(page.entries, isEmpty);
      expect(page.userNames, isEmpty);
      expect(page.hasOlderEntries, isFalse);
    });
  });
}
