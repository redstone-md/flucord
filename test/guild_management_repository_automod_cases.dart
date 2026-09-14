part of 'guild_management_repository_test.dart';

const _guild = '111111111111111111';
const _ruleId = '222222222222222222';

Map<String, Object?> _wireRule({int trigger = 1}) => {
  'id': _ruleId,
  'guild_id': _guild,
  'name': 'No invites',
  'event_type': 1,
  'trigger_type': trigger,
  'trigger_metadata': {
    'keyword_filter': ['discord.gg/*'],
  },
  'actions': [
    {'type': 1, 'metadata': <String, Object?>{}},
  ],
  'enabled': true,
};

const _keywordDraft = AutoModRuleDraft(
  name: 'No invites',
  eventType: AutoModEventType.messageSend,
  triggerType: AutoModTriggerType.keyword,
  metadata: AutoModTriggerMetadata(keywordFilter: ['discord.gg/*']),
  actions: [AutoModAction(type: AutoModActionType.blockMessage)],
);

void _automodCases() {
  group('automod', () {
    test('lists the rules a guild holds', () async {
      final transport = _Transport([
        _json([_wireRule()]),
      ]);

      final rules = await _repository(transport).loadAutoModRules(_guild);

      expect(rules.single.name, 'No invites');
      expect(
        transport.requests.single.uri.path,
        endsWith('/guilds/$_guild/auto-moderation/rules'),
      );
      expect(transport.requests.single.method, 'GET');
    });

    test('creates a rule and attributes it in the audit log', () async {
      final transport = _Transport([_json(_wireRule())]);

      final rule = await _repository(transport).createAutoModRule(
        guildId: _guild,
        draft: _keywordDraft,
        reason: 'raid response',
      );

      expect(rule.id, _ruleId);
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.json?['trigger_type'], 1);
      expect(request.json?['actions'], [
        {'type': 1, 'metadata': <String, Object?>{}},
      ]);
      expect(
        request.headers[DiscordRestClient.auditLogReasonHeader],
        'raid%20response',
      );
    });

    test('a create the server answered without an id is an error', () async {
      final transport = _Transport([_json(const <String, Object?>{})]);

      await expectLater(
        _repository(
          transport,
        ).createAutoModRule(guildId: _guild, draft: _keywordDraft),
        throwsA(isA<DiscordApiException>()),
      );
    });

    test('patches only what the edit carries', () async {
      final transport = _Transport([_json(_wireRule())]);
      final edit = AutoModRuleEdit()..enabled = false;

      await _repository(
        transport,
      ).updateAutoModRule(guildId: _guild, ruleId: _ruleId, edit: edit);

      final request = transport.requests.single;
      expect(request.method, 'PATCH');
      expect(request.uri.path, endsWith('/rules/$_ruleId'));
      expect(request.json, {'enabled': false});
    });

    test('deletes a rule', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);

      await _repository(
        transport,
      ).deleteAutoModRule(guildId: _guild, ruleId: _ruleId, reason: 'obsolete');

      final request = transport.requests.single;
      expect(request.method, 'DELETE');
      expect(request.uri.path, endsWith('/rules/$_ruleId'));
      expect(
        request.headers[DiscordRestClient.auditLogReasonHeader],
        'obsolete',
      );
    });

    test('validation asks the server and reports its verdict', () async {
      final accepted = _Transport([_json(const <String, Object?>{})]);

      expect(
        await _repository(
          accepted,
        ).validateAutoModRule(guildId: _guild, draft: _keywordDraft),
        isNull,
      );
      expect(accepted.requests.single.uri.path, endsWith('/rules/validate'));
      expect(accepted.requests.single.method, 'POST');
    });

    test('a refused draft answers with the refusal, not an error', () async {
      final refused = _Transport([
        DiscordHttpResponse(
          statusCode: 400,
          headers: const {},
          body: jsonEncode({'message': 'Invalid regex'}),
        ),
      ]);

      expect(
        await _repository(
          refused,
        ).validateAutoModRule(guildId: _guild, draft: _keywordDraft),
        contains('Invalid regex'),
      );
    });

    test('a validation that could not be asked is still an error', () async {
      // Being refused the route is not the server saying the rule is wrong,
      // and reporting it as one would tell the moderator to fix a rule that is
      // fine. Only a 400 is a verdict on the draft.
      final forbidden = _Transport([
        DiscordHttpResponse(
          statusCode: 403,
          headers: const {},
          body: jsonEncode({'message': 'Missing permissions'}),
        ),
      ]);

      await expectLater(
        _repository(
          forbidden,
        ).validateAutoModRule(guildId: _guild, draft: _keywordDraft),
        throwsA(isA<DiscordApiException>()),
      );
    });

    test('the raid controls post to their own routes', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      final repository = _repository(transport);

      await repository.clearMentionRaid(_guild);
      await repository.reportMentionRaidFalseAlarm(_guild);

      expect(transport.requests.first.method, 'POST');
      expect(
        transport.requests.first.uri.path,
        endsWith('/auto-moderation/clear-mention-raid'),
      );
      expect(
        transport.requests.last.uri.path,
        endsWith('/auto-moderation/false-alarm'),
      );
    });
  });
}
