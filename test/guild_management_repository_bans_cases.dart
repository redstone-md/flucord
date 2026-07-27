part of 'guild_management_repository_test.dart';

void _bansCases() {
  group('bans', () {
    test('a single ban puts the reason in the header', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      final result = await _repository(transport).banMembers(
        guildId: '111111111111111111',
        request: const BanRequest(
          userIds: ['123456789012345678'],
          deletion: BanMessageDeletion.lastDay,
          reason: 'Raiding the server',
        ),
      );
      final request = transport.requests.single;
      expect(request.method, 'PUT');
      expect(request.uri.path, endsWith('/bans/123456789012345678'));
      expect(request.json, {'delete_message_seconds': 86400});
      expect(
        request.headers[DiscordRestClient.auditLogReasonHeader],
        Uri.encodeComponent('Raiding the server'),
      );
      expect(result.bannedUserIds, ['123456789012345678']);
      expect(result.isCompleteSuccess, isTrue);
    });

    test('a reason with a newline cannot split the request', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      await _repository(transport).banMembers(
        guildId: '111111111111111111',
        request: const BanRequest(
          userIds: ['123456789012345678'],
          reason: 'line one\r\nX-Injected: yes',
        ),
      );
      final header = transport
          .requests
          .single
          .headers[DiscordRestClient.auditLogReasonHeader]!;
      expect(header, isNot(contains('\n')));
      expect(header, contains('%0D%0A'));
    });

    test('a blank reason sends no header at all', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      await _repository(transport).banMembers(
        guildId: '111111111111111111',
        request: const BanRequest(
          userIds: ['123456789012345678'],
          reason: '  ',
        ),
      );
      expect(
        transport.requests.single.headers.containsKey(
          DiscordRestClient.auditLogReasonHeader,
        ),
        isFalse,
      );
    });

    test('more than one user goes to the bulk route', () async {
      final transport = _Transport([
        _json({
          'banned_users': ['123456789012345678'],
          'failed_users': ['222222222222222222'],
        }),
      ]);
      final result = await _repository(transport).banMembers(
        guildId: '111111111111111111',
        request: const BanRequest(
          userIds: ['123456789012345678', '222222222222222222'],
          moderatorReportId: '333333333333333333',
        ),
      );
      expect(transport.requests.single.uri.path, endsWith('/bulk-ban'));
      expect(transport.requests.single.json, {
        'user_ids': ['123456789012345678', '222222222222222222'],
        'delete_message_seconds': 3600,
      });
      expect(result.failedUserIds, ['222222222222222222']);
    });

    test('an empty selection sends nothing', () async {
      final transport = _Transport([]);
      final result = await _repository(transport).banMembers(
        guildId: '111111111111111111',
        request: const BanRequest(userIds: []),
      );
      expect(transport.requests, isEmpty);
      expect(result.bannedUserIds, isEmpty);
    });

    test('a moderator report id rides along on a single ban', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      await _repository(transport).banMembers(
        guildId: '111111111111111111',
        request: const BanRequest(
          userIds: ['123456789012345678'],
          deletion: BanMessageDeletion.moderatorReportDefault,
          moderatorReportId: '987654321098765432',
        ),
      );
      expect(transport.requests.single.json, {
        'delete_message_seconds': 0,
        'moderator_report_id': '987654321098765432',
      });
    });

    test('the ban page size is clamped', () async {
      final transport = _Transport([_json(<Object?>[]), _json(<Object?>[])]);
      final repository = _repository(transport);
      await repository.loadBans(guildId: '111111111111111111', limit: 99999);
      expect(transport.requests.first.uri.queryParameters['limit'], '1000');
      await repository.loadBans(
        guildId: '111111111111111111',
        limit: 25,
        after: '123456789012345678',
      );
      expect(transport.requests.last.uri.queryParameters, {
        'limit': '25',
        'after': '123456789012345678',
      });
    });

    test('a blank search query is dropped', () async {
      final transport = _Transport([_json(<Object?>[]), _json(<Object?>[])]);
      final repository = _repository(transport);
      await repository.searchBans(guildId: '111111111111111111', query: '  ');
      expect(
        transport.requests.first.uri.queryParameters.containsKey('query'),
        isFalse,
      );
      await repository.searchBans(
        guildId: '111111111111111111',
        query: ' raider ',
      );
      expect(transport.requests.last.uri.queryParameters['query'], 'raider');
    });

    test('unban carries a reason header', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      await _repository(transport).unbanMember(
        guildId: '111111111111111111',
        userId: '123456789012345678',
        reason: 'appeal accepted',
      );
      expect(transport.requests.single.method, 'DELETE');
      expect(
        transport.requests.single.headers[DiscordRestClient
            .auditLogReasonHeader],
        'appeal%20accepted',
      );
    });

    test('kick puts its reason in the query, not the header', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      final repository = _repository(transport);
      await repository.kickMember(
        guildId: '111111111111111111',
        userId: '123456789012345678',
        reason: 'spam',
      );
      final request = transport.requests.first;
      expect(request.uri.path, endsWith('/members/123456789012345678'));
      expect(request.uri.queryParameters['reason'], 'spam');
      expect(
        request.headers.containsKey(DiscordRestClient.auditLogReasonHeader),
        isFalse,
      );

      await repository.kickMember(
        guildId: '111111111111111111',
        userId: '123456789012345678',
        reason: '   ',
      );
      expect(
        transport.requests.last.uri.queryParameters.containsKey('reason'),
        isFalse,
      );
    });
  });
}
