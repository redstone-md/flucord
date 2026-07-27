import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_guild_management_repository.dart';
import 'package:flucord/src/data/discord/discord_moderation_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/moderation_report.dart';

part 'guild_management_repository_bans_cases.dart';

void main() {
  group('guild overview', () {
    test('reads and writes a partial patch', () async {
      final transport = _Transport([
        _json({'id': '111111111111111111', 'name': 'The Forge'}),
        _json({'id': '111111111111111111', 'name': 'Renamed'}),
      ]);
      final repository = _repository(transport);
      final settings = await repository.loadGuildOverview('111111111111111111');
      expect(settings.name, 'The Forge');
      expect(
        transport.requests.first.uri.path,
        endsWith('/guilds/111111111111111111'),
      );

      final patch = GuildOverviewPatch()
        ..name = 'Renamed'
        ..afkChannelId = null;
      final saved = await repository.saveGuildOverview(
        guildId: '111111111111111111',
        patch: patch,
      );
      expect(saved.name, 'Renamed');
      expect(transport.requests.last.method, 'PATCH');
      // A null body value survives: on this route it means "clear the field",
      // which is not the same request as leaving the key out.
      expect(transport.requests.last.json, {
        'name': 'Renamed',
        'afk_channel_id': null,
      });
    });
  });

  group('roles', () {
    test('creates, updates, deletes and reorders', () async {
      final transport = _Transport([
        _json([
          {'id': '222222222222222222', 'name': 'mod', 'permissions': '8'},
        ]),
        _json({'id': '333333333333333333', 'name': 'new role'}),
        _json({'id': '333333333333333333', 'name': 'renamed'}),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        _json(<Object?>[]),
      ]);
      final repository = _repository(transport);
      final roles = await repository.loadRoles('111111111111111111');
      expect(roles.single.permissions, BigInt.from(8));

      await repository.createRole(
        guildId: '111111111111111111',
        draft: const GuildRoleDraft(name: 'new role'),
      );
      expect(transport.requests[1].json, {
        'name': 'new role',
        'color': 0,
        'colors': {
          'primary_color': 0,
          'secondary_color': null,
          'tertiary_color': null,
        },
        'permissions': '0',
      });

      final edit = GuildRoleEdit()
        ..name = 'renamed'
        ..hoist = true
        ..mentionable = false
        ..colorValue = 0x4c9b72
        ..unicodeEmoji = null
        ..icon = null
        ..permissions = BigInt.parse('9007199254740992');
      await repository.updateRole(
        guildId: '111111111111111111',
        roleId: '333333333333333333',
        edit: edit,
      );
      expect(transport.requests[2].method, 'PATCH');
      // The bitfield travels as a decimal string; a JSON number would round the
      // top bits away.
      expect(transport.requests[2].json!['permissions'], '9007199254740992');
      expect(transport.requests[2].json!['icon'], isNull);
      expect(transport.requests[2].json!.containsKey('unicode_emoji'), isTrue);

      await repository.deleteRole(
        guildId: '111111111111111111',
        roleId: '333333333333333333',
      );
      expect(transport.requests[3].method, 'DELETE');

      await repository.reorderRoles(
        guildId: '111111111111111111',
        deltas: const [
          RolePositionDelta(id: '222222222222222222', position: 2),
        ],
      );
      expect(transport.requests[4].method, 'PATCH');
      expect(transport.requests[4].uri.path, endsWith('/roles'));
      // A bare JSON array, not an object wrapping one.
      expect(transport.requests[4].decoded, [
        {'id': '222222222222222222', 'position': 2},
      ]);
    });

    test('an empty reorder is never sent', () async {
      final transport = _Transport([]);
      await _repository(
        transport,
      ).reorderRoles(guildId: '111111111111111111', deltas: const []);
      expect(transport.requests, isEmpty);
    });

    test('a role edit refuses a negative bitfield', () {
      expect(
        () => GuildRoleEdit().permissions = BigInt.from(-1),
        throwsArgumentError,
      );
    });

    test('a role icon must be a data URI or null', () {
      expect(() => GuildRoleEdit().icon = 'cdnhash', throwsArgumentError);
      expect(() => GuildOverviewPatch().icon = 'cdnhash', throwsArgumentError);
    });
  });

  group('channels', () {
    test('creates, edits, deletes and batches positions', () async {
      final transport = _Transport([
        _json({
          'id': '222222222222222222',
          'name': 'general',
          'type': 0,
          'guild_id': '111111111111111111',
        }),
        _json({
          'id': '222222222222222222',
          'name': 'renamed',
          'type': 0,
          'guild_id': '111111111111111111',
        }),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        _json(<Object?>[]),
      ]);
      final repository = _repository(transport);
      final created = await repository.createGuildChannel(
        guildId: '111111111111111111',
        draft: const GuildChannelDraft(
          type: GuildChannelType.text,
          name: 'general',
          topic: 'talk',
          parentId: '333333333333333333',
          userLimit: 0,
        ),
      );
      expect(created.name, 'general');
      expect(transport.requests.first.json, {
        'type': 0,
        'name': 'general',
        'permission_overwrites': <Object?>[],
        'topic': 'talk',
        'parent_id': '333333333333333333',
      });

      final edited = await repository.editGuildChannel(
        channelId: '222222222222222222',
        edit: GuildChannelEdit()
          ..name = 'renamed'
          ..rateLimitPerUser = 30,
      );
      expect(edited.name, 'renamed');
      expect(transport.requests[1].json, {
        'name': 'renamed',
        'rate_limit_per_user': 30,
      });

      await repository.deleteGuildChannel('222222222222222222');
      expect(transport.requests[2].method, 'DELETE');

      await repository.reorderGuildChannels(
        guildId: '111111111111111111',
        deltas: const [
          ChannelPositionDelta(
            id: '222222222222222222',
            position: 1,
            parentId: null,
            hasParentId: true,
            lockPermissions: true,
          ),
        ],
      );
      expect(transport.requests[3].decoded, [
        {
          'id': '222222222222222222',
          'position': 1,
          'parent_id': null,
          'lock_permissions': true,
        },
      ]);
    });

    test('a category still comes back as a channel record', () async {
      final transport = _Transport([
        _json({'id': '333333333333333333', 'name': 'Voice', 'type': 4}),
      ]);
      final created = await _repository(transport).createGuildChannel(
        guildId: '111111111111111111',
        draft: const GuildChannelDraft(
          type: GuildChannelType.category,
          name: 'Voice',
        ),
      );
      expect(created.id, '333333333333333333');
      expect(created.name, 'Voice');
      expect(created.spaceId, '111111111111111111');
    });

    test('slowmode is bounded before it reaches the wire', () {
      expect(
        () => GuildChannelEdit().rateLimitPerUser = 21601,
        throwsArgumentError,
      );
      expect(
        () => GuildChannelEdit().rateLimitPerUser = -1,
        throwsArgumentError,
      );
    });

    test('an empty channel batch is never sent', () async {
      final transport = _Transport([]);
      await _repository(
        transport,
      ).reorderGuildChannels(guildId: '111111111111111111', deltas: const []);
      expect(transport.requests, isEmpty);
    });
  });

  _bansCases();

  group('invites', () {
    test('lists, creates and revokes', () async {
      final transport = _Transport([
        _json([
          {'code': 'forge', 'uses': 1},
        ]),
        _json({'code': 'fresh', 'max_age': 3600}),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      final repository = _repository(transport);
      final invites = await repository.loadGuildInvites('111111111111111111');
      expect(invites.single.code, 'forge');

      final created = await repository.createChannelInvite(
        channelId: '222222222222222222',
        options: const InviteOptions(maxAgeSeconds: 3600, roleIds: []),
      );
      expect(created.code, 'fresh');
      // `role_ids` is dropped when empty rather than sent as [], which on this
      // route would read as "grant no roles".
      expect(transport.requests[1].json, {
        'max_age': 3600,
        'max_uses': 0,
        'temporary': false,
        'unique': false,
      });

      await repository.revokeInvite('for ge/1');
      expect(
        transport.requests.last.uri.path,
        endsWith('/invites/for%20ge%2F1'),
      );
    });

    test('role ids survive when there are some', () async {
      final transport = _Transport([
        _json({'code': 'x'}),
      ]);
      await _repository(transport).createChannelInvite(
        channelId: '222222222222222222',
        options: const InviteOptions(roleIds: ['333333333333333333']),
      );
      expect(transport.requests.single.json!['role_ids'], [
        '333333333333333333',
      ]);
    });

    test('an invite response with no code is a transport failure', () async {
      final transport = _Transport([
        _json({'uses': 0}),
      ]);
      expect(
        () => _repository(
          transport,
        ).createChannelInvite(channelId: '222222222222222222'),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('audit log', () {
    test('sends the page size and drops the empty filters', () async {
      final transport = _Transport([
        _json({'audit_log_entries': <Object?>[]}),
      ]);
      await _repository(transport).loadAuditLog(guildId: '111111111111111111');
      expect(transport.requests.single.uri.queryParameters, {'limit': '50'});
    });

    test('sends the filters it was given', () async {
      final transport = _Transport([
        _json({'audit_log_entries': <Object?>[]}),
      ]);
      await _repository(transport).loadAuditLog(
        guildId: '111111111111111111',
        query: const AuditLogQuery(
          before: '987654321098765432',
          action: AuditLogActionType.memberBanAdd,
        ),
      );
      expect(transport.requests.single.uri.queryParameters, {
        'limit': '50',
        'before': '987654321098765432',
        'action_type': '22',
      });
    });
  });

  group('moderation routes', () {
    test('fetches the report menu with its variant', () async {
      final transport = _Transport([
        _json({
          'root_node_id': 'root',
          'success_node_id': 'ok',
          'fail_node_id': 'bad',
          'nodes': {
            'root': {'id': 'root'},
          },
        }),
      ]);
      final menu = await DiscordModerationRepository(
        _client(transport),
      ).loadReportMenu(ReportType.message, variant: 'staff');
      expect(menu.rootNodeId, 'root');
      expect(
        transport.requests.single.uri.path,
        endsWith('/reporting/menu/message'),
      );
      expect(transport.requests.single.uri.queryParameters['variant'], 'staff');
    });

    test('a menu without a graph fails rather than opening empty', () {
      final transport = _Transport([
        _json({'nodes': 'nope'}),
      ]);
      expect(
        () => DiscordModerationRepository(
          _client(transport),
        ).loadReportMenu(ReportType.user),
        throwsA(isA<DiscordApiException>()),
      );
    });

    test('submits a report and reads its id', () async {
      final transport = _Transport([
        _json({'report_id': '987654321098765432'}),
        _json({'no_id': true}),
      ]);
      final repository = DiscordModerationRepository(_client(transport));
      const submission = ReportSubmission(
        type: ReportType.user,
        body: {'name': 'user'},
      );
      expect(await repository.submitReport(submission), '987654321098765432');
      expect(transport.requests.first.uri.path, endsWith('/reporting/user'));
      expect(await repository.submitReport(submission), isNull);
    });

    test('block, unblock, ignore and unignore hit their own routes', () async {
      final transport = _Transport([
        for (var index = 0; index < 4; index++)
          const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      final repository = DiscordModerationRepository(_client(transport));
      await repository.blockUser('123456789012345678');
      await repository.unblockUser('123456789012345678');
      await repository.ignoreUser('123456789012345678');
      await repository.unignoreUser('123456789012345678');
      expect(transport.requests[0].method, 'PUT');
      expect(transport.requests[0].json, {'type': 2});
      expect(
        transport.requests[0].uri.path,
        endsWith('/users/@me/relationships/123456789012345678'),
      );
      expect(transport.requests[1].method, 'DELETE');
      expect(transport.requests[2].uri.path, endsWith('/ignore'));
      expect(transport.requests[3].method, 'DELETE');
      expect(transport.requests[3].uri.path, endsWith('/ignore'));
    });
  });
}

DiscordGuildManagementRepository _repository(_Transport transport) =>
    DiscordGuildManagementRepository(_client(transport));

DiscordRestClient _client(_Transport transport) => DiscordRestClient(
  authorization: DiscordDesktopAuthorization('token'),
  transport: transport,
  baseUri: Uri.parse('https://discord.com/api/v9'),
);

DiscordHttpResponse _json(Object? payload) => DiscordHttpResponse(
  statusCode: 200,
  headers: const {},
  body: jsonEncode(payload),
);

final class _Recorded {
  const _Recorded({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? body;

  Object? get decoded => body == null ? null : jsonDecode(utf8.decode(body!));

  Map<String, Object?>? get decodedMap {
    final value = decoded;
    return value is Map ? value.cast<String, Object?>() : null;
  }

  Map<String, Object?>? get json => decodedMap;
}

final class _Transport implements DiscordHttpTransport {
  _Transport(this._responses);

  final List<DiscordHttpResponse> _responses;
  final List<_Recorded> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(
      _Recorded(
        method: method,
        uri: uri,
        headers: Map.unmodifiable(headers),
        body: body,
      ),
    );
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
