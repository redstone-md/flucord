part of 'guild_management_repository_test.dart';

const _gateGuild = '100000000000000301';
const _gateAccount = '100000000000000302';
const _gateRole = '100000000000000303';
const _gateChannel = '100000000000000304';

Map<String, Object?> _ownMember({required bool pending, List<String>? roles}) =>
    {
      'user': {'id': _gateAccount, 'username': 'pat'},
      'roles': roles ?? const <String>[],
      'pending': pending,
      'flags': 0,
    };

/// Rules screening and onboarding, as a new member's client asks for them.
void _joinGateCases() {
  group('rules screening', () {
    test('reads the rules a server screens new members with', () async {
      final transport = _Transport([
        _json({
          'version': '2026-11-01T10:00:00.000000+00:00',
          'description': 'A place for plants.',
          'form_fields': [
            {
              'field_type': 'TERMS',
              'label': 'Read and agree to the server rules',
              'values': ['Be kind.', 'No spam.'],
              'required': true,
              'description': null,
              'automations': null,
            },
          ],
        }),
      ]);

      final screening = await _repository(
        transport,
      ).loadRulesScreening(_gateGuild);

      expect(transport.requests.single.method, 'GET');
      expect(
        transport.requests.single.uri.path,
        endsWith('/guilds/$_gateGuild/member-verification'),
      );
      expect(screening?.description, 'A place for plants.');
      expect(screening?.rules, ['Be kind.', 'No spam.']);
      expect(screening?.canAccept, isTrue);
    });

    test('a server with no screening answers none', () async {
      final transport = _Transport([
        const DiscordHttpResponse(
          statusCode: 404,
          headers: {},
          body: '{"message": "Unknown Guild Member Verification Form"}',
        ),
      ]);

      expect(
        await _repository(transport).loadRulesScreening(_gateGuild),
        isNull,
      );
    });

    test('a required written question cannot be accepted here', () async {
      final transport = _Transport([
        _json({
          'version': null,
          'form_fields': [
            {
              'field_type': 'TERMS',
              'label': 'Rules',
              'values': ['Be kind.'],
              'required': true,
            },
            {
              'field_type': 'TEXT_INPUT',
              'label': 'Why are you here?',
              'required': true,
            },
          ],
        }),
      ]);

      final screening = await _repository(
        transport,
      ).loadRulesScreening(_gateGuild);

      expect(screening?.canAccept, isFalse);
    });

    test('accepting sends every field back agreed, then reads the member '
        'again', () async {
      final transport = _Transport([
        _json({
          'id': '100000000000000305',
          'guild_id': _gateGuild,
          'application_status': 'APPROVED',
        }),
        _json(_ownMember(pending: false)),
      ]);
      const screening = RulesScreening(
        version: '2026-11-01T10:00:00.000000+00:00',
        fields: [
          RulesScreeningField(
            type: 'TERMS',
            label: 'Read and agree to the server rules',
            required: true,
            rules: ['Be kind.', 'No spam.'],
          ),
        ],
      );

      final member = await _repository(
        transport,
      ).acceptRules(guildId: _gateGuild, screening: screening);

      final accept = transport.requests.first;
      expect(accept.method, 'PUT');
      expect(accept.uri.path, endsWith('/guilds/$_gateGuild/requests/@me'));
      expect(accept.json, {
        'version': '2026-11-01T10:00:00.000000+00:00',
        'form_fields': [
          {
            'field_type': 'TERMS',
            'label': 'Read and agree to the server rules',
            'required': true,
            'description': null,
            'values': ['Be kind.', 'No spam.'],
            'response': true,
          },
        ],
      });
      expect(transport.requests.last.method, 'GET');
      expect(
        transport.requests.last.uri.path,
        endsWith('/guilds/$_gateGuild/members/@me'),
      );
      expect(member?.membershipIn(_gateGuild)?.isPending, isFalse);
    });

    test('a refused accept says why', () async {
      final transport = _Transport([
        const DiscordHttpResponse(
          statusCode: 400,
          headers: {},
          body: '{"message": "The rules changed", "code": 150009}',
        ),
      ]);

      await expectLater(
        _repository(transport).acceptRules(
          guildId: _gateGuild,
          screening: const RulesScreening(fields: []),
        ),
        throwsA(
          isA<GuildJoinGateRefusal>().having(
            (refusal) => refusal.message,
            'message',
            contains('The rules changed'),
          ),
        ),
      );
    });
  });

  group('onboarding', () {
    test('reads the prompts shown while joining', () async {
      final transport = _Transport([
        _json({
          'guild_id': _gateGuild,
          'enabled': true,
          'mode': 0,
          'default_channel_ids': ['100000000000000306'],
          'prompts': [
            {
              'id': '100000000000000307',
              'title': 'What brings you here?',
              'single_select': true,
              'required': true,
              'in_onboarding': true,
              'type': 0,
              'options': [
                {
                  'id': '100000000000000308',
                  'title': 'Gardening',
                  'description': 'Tips and photos',
                  'emoji': {'id': null, 'name': '🌱'},
                  'role_ids': [_gateRole],
                  'channel_ids': [_gateChannel],
                },
              ],
            },
            {
              'id': '100000000000000309',
              'title': 'Only in Customize',
              'single_select': false,
              'required': false,
              'in_onboarding': false,
              'type': 0,
              'options': const <Object?>[],
            },
          ],
        }),
      ]);

      final onboarding = await _repository(
        transport,
      ).loadOnboarding(_gateGuild);

      expect(transport.requests.single.method, 'GET');
      expect(
        transport.requests.single.uri.path,
        endsWith('/guilds/$_gateGuild/onboarding'),
      );
      expect(onboarding?.defaultChannelIds, ['100000000000000306']);
      final prompt = onboarding!.prompts.single;
      expect(prompt.title, 'What brings you here?');
      expect(prompt.singleSelect, isTrue);
      expect(prompt.required, isTrue);
      final option = prompt.options.single;
      expect(option.title, 'Gardening');
      expect(option.description, 'Tips and photos');
      expect(option.emoji, '🌱');
      expect(option.roleIds, [_gateRole]);
      expect(option.channelIds, [_gateChannel]);
    });

    test('a server with onboarding off, or refused, asks nothing', () async {
      final off = _Transport([
        _json({
          'guild_id': _gateGuild,
          'enabled': false,
          'prompts': const <Object?>[],
        }),
      ]);
      expect(await _repository(off).loadOnboarding(_gateGuild), isNull);

      final refused = _Transport([
        const DiscordHttpResponse(
          statusCode: 403,
          headers: {},
          body: '{"message": "Missing Access", "code": 50001}',
        ),
      ]);
      expect(await _repository(refused).loadOnboarding(_gateGuild), isNull);
    });

    test('answering sends the picks and what was seen, then reads the member '
        'again', () async {
      final transport = _Transport([
        _json({
          'guild_id': _gateGuild,
          'user_id': _gateAccount,
          'onboarding_responses': ['100000000000000308'],
        }),
        _json(_ownMember(pending: false, roles: [_gateRole])),
      ]);
      const onboarding = GuildOnboarding(
        guildId: _gateGuild,
        prompts: [
          OnboardingPrompt(
            id: '100000000000000307',
            title: 'What brings you here?',
            options: [
              OnboardingOption(id: '100000000000000308', title: 'Gardening'),
              OnboardingOption(id: '100000000000000310', title: 'Cooking'),
            ],
          ),
        ],
      );
      final seenAt = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);

      final member = await _repository(transport).answerOnboarding(
        guildId: _gateGuild,
        onboarding: onboarding,
        chosenOptionIds: {'100000000000000308'},
        seenAt: seenAt,
      );

      final answer = transport.requests.first;
      expect(answer.method, 'PUT');
      expect(
        answer.uri.path,
        endsWith('/guilds/$_gateGuild/onboarding-responses'),
      );
      expect(answer.json, {
        'onboarding_responses': ['100000000000000308'],
        'onboarding_prompts_seen': {'100000000000000307': 1000},
        'onboarding_responses_seen': {
          '100000000000000308': 1000,
          '100000000000000310': 1000,
        },
      });
      expect(
        transport.requests.last.uri.path,
        endsWith('/guilds/$_gateGuild/members/@me'),
      );
      expect(member?.membershipIn(_gateGuild)?.roleIds, [_gateRole]);
    });
  });
}
