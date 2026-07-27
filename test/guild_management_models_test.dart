import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/moderation_report.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';

import 'support/guild_settings_fixtures.dart';

void main() {
  group('GuildOverviewPatch', () {
    test('starts empty and records only what it is given', () {
      final patch = GuildOverviewPatch();
      expect(patch.isEmpty, isTrue);
      expect(patch.isNotEmpty, isFalse);
      expect(patch.keys, isEmpty);
      expect(patch.contains('name'), isFalse);

      patch
        ..name = 'The Forge'
        ..description = null
        ..icon = 'data:image/png;base64,AAAA'
        ..preferredLocale = 'en-GB'
        ..afkChannelId = '222222222222222222'
        ..afkTimeoutSeconds = 900
        ..systemChannelId = null
        ..systemChannelFlags = 9
        ..verificationLevel = GuildVerificationLevel.high
        ..explicitContentFilter = GuildExplicitContentFilter.allMembers
        ..defaultMessageNotifications = GuildNotificationLevel.onlyMentions
        ..premiumProgressBarEnabled = true;

      expect(patch.isEmpty, isFalse);
      expect(patch.isNotEmpty, isTrue);
      expect(patch.contains('name'), isTrue);
      expect(patch['afk_timeout'], 900);
      expect(patch.keys, contains('preferred_locale'));
      expect(patch.toJson(), {
        'name': 'The Forge',
        // A present null is "clear it", which is why it survives to the body.
        'description': null,
        'icon': 'data:image/png;base64,AAAA',
        'preferred_locale': 'en-GB',
        'afk_channel_id': '222222222222222222',
        'afk_timeout': 900,
        'system_channel_id': null,
        'system_channel_flags': 9,
        'verification_level': 3,
        'explicit_content_filter': 2,
        'default_message_notifications': 1,
        'premium_progress_bar_enabled': true,
      });
    });

    test('clearing the icon is a null, not a hash', () {
      final patch = GuildOverviewPatch()..icon = null;
      expect(patch.toJson(), {'icon': null});
    });
  });

  group('GuildSystemChannelFlags', () {
    test('reads and rewrites one bit without touching the others', () {
      const unknownBit = 1 << 20;
      final flags =
          GuildSystemChannelFlags.suppressPremiumSubscriptions | unknownBit;
      expect(
        GuildSystemChannelFlags.has(
          flags,
          GuildSystemChannelFlags.suppressJoinNotifications,
        ),
        isFalse,
      );
      final set = GuildSystemChannelFlags.withFlag(
        flags,
        GuildSystemChannelFlags.suppressJoinNotifications,
        enabled: true,
      );
      expect(
        GuildSystemChannelFlags.has(
          set,
          GuildSystemChannelFlags.suppressJoinNotifications,
        ),
        isTrue,
      );
      // The bit this build has no name for is still there.
      expect(set & unknownBit, unknownBit);
      final cleared = GuildSystemChannelFlags.withFlag(
        set,
        GuildSystemChannelFlags.suppressJoinNotifications,
        enabled: false,
      );
      expect(cleared, flags);
    });
  });

  test('BanMessageDeletion reads its wire value', () {
    expect(BanMessageDeletion.fromWire(604800), BanMessageDeletion.lastWeek);
    expect(BanMessageDeletion.fromWire('0'), BanMessageDeletion.none);
    expect(BanMessageDeletion.fromWire(7), isNull);
    expect(BanMessageDeletion.standardDefault, BanMessageDeletion.lastHour);
    expect(BanMessageDeletion.moderatorReportDefault, BanMessageDeletion.none);
  });

  test('GuildMfaLevel reads its wire value', () {
    expect(GuildMfaLevel.fromWire(1), GuildMfaLevel.elevated);
    expect(GuildMfaLevel.fromWire(4), isNull);
  });

  test('GuildRoleDraft defaults to a role that grants nothing', () {
    const draft = GuildRoleDraft();
    expect(draft.grantedPermissions, BigInt.zero);
    expect(draft.toJson()['permissions'], '0');
    expect(draft.toJson().containsKey('name'), isFalse);
    final granted = GuildRoleDraft(
      name: 'mod',
      colorValue: 7,
      permissions: BigInt.from(8),
    );
    expect(granted.toJson()['permissions'], '8');
    expect(granted.toJson()['colors'], {
      'primary_color': 7,
      'secondary_color': null,
      'tertiary_color': null,
    });
  });

  test('GuildRoleEdit reports what it will send', () {
    final edit = GuildRoleEdit();
    expect(edit.isEmpty, isTrue);
    expect(edit.isNotEmpty, isFalse);
    expect(edit.keys, isEmpty);
    edit
      ..name = 'mod'
      ..icon = 'data:image/png;base64,AAAA'
      ..unicodeEmoji = '🔨';
    expect(edit.isNotEmpty, isTrue);
    expect(edit.keys, containsAll(['name', 'icon', 'unicode_emoji']));
    expect(edit['name'], 'mod');
  });

  test('GuildChannelEdit carries every field the route takes', () {
    final edit = GuildChannelEdit();
    expect(edit.isEmpty, isTrue);
    expect(edit.keys, isEmpty);
    edit
      ..name = 'general'
      ..topic = null
      ..nsfw = true
      ..bitrate = 64000
      ..userLimit = 10
      ..parentId = '333333333333333333'
      ..rateLimitPerUser = 0;
    expect(edit.isNotEmpty, isTrue);
    expect(edit['nsfw'], true);
    expect(edit.toJson(), {
      'name': 'general',
      'topic': null,
      'nsfw': true,
      'bitrate': 64000,
      'user_limit': 10,
      'parent_id': '333333333333333333',
      'rate_limit_per_user': 0,
    });
  });

  test('GuildChannelDraft drops the fields Discord omits', () {
    const draft = GuildChannelDraft(
      type: GuildChannelType.voice,
      name: 'workbench',
      topic: '',
      userLimit: 0,
    );
    expect(draft.toJson(), {
      'type': 2,
      'name': 'workbench',
      'permission_overwrites': <Object?>[],
    });
  });

  test('a report target built at runtime still names its keys', () {
    // Constructed rather than const so the sealed base runs its constructor.
    final target = MessageReportTarget(
      channelId: '222222222222222222'.toString(),
      messageId: '333333333333333333'.toString(),
    );
    expect(target.toEntityKeys(), hasLength(2));
    final user = UserReportTarget(userId: '123456789012345678'.toString());
    expect(user.type, ReportType.user);
    final guild = GuildReportTarget('111111111111111111'.toString());
    expect(guild.guildId, '111111111111111111');
  });

  test('the report flow exposes what was typed on the node in view', () {
    final flow = ReportFlow(
      menu: const ReportMenu(
        nodes: {'root': ReportNode(id: 'root')},
        rootNodeId: 'root',
        successNodeId: 'root',
        failNodeId: 'root',
      ),
      target: const GuildReportTarget('111111111111111111'),
    );
    flow.setValue('note', 'typed');
    expect(flow.textInput, {'note': 'typed'});
  });

  test('a guild-wide permission the account holds answers true', () {
    final permissions = WorkspacePermissions(
      guildWorkspace(),
      memberId: moderatorId,
    );
    expect(
      permissions.canInSpace(DiscordPermissions.banMembers, guildId),
      isTrue,
    );
    expect(
      permissions.canInSpace(DiscordPermissions.administrator, guildId),
      isFalse,
    );
  });

  group('query encoding', () {
    test('a list repeats the key and a bool renders lowercase', () async {
      final transport = _Transport();
      final client = DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      );
      await client.getList(
        '/guilds/111111111111111111/prune',
        query: {
          'days': 7,
          'compute': true,
          'quiet': false,
          'include_roles': ['222222222222222222', '333333333333333333', null],
          'empty': <String>[],
          'skipped': null,
        },
      );
      final query = transport.uri!.queryParametersAll;
      expect(query['days'], ['7']);
      expect(query['compute'], ['true']);
      expect(query['quiet'], ['false']);
      expect(query['include_roles'], [
        '222222222222222222',
        '333333333333333333',
      ]);
      // An empty list and a null are both dropped: neither is a filter.
      expect(query.containsKey('empty'), isFalse);
      expect(query.containsKey('skipped'), isFalse);
    });
  });
}

final class _Transport implements DiscordHttpTransport {
  Uri? uri;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    this.uri = uri;
    return DiscordHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(const <Object?>[]),
    );
  }

  @override
  void close() {}
}
