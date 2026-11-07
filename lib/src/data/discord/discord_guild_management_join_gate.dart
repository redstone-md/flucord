part of 'discord_guild_management_repository.dart';

/// Rules screening and onboarding: what a new member's client asks for right
/// after a join.
///
/// Both answers read this account's member row back, because that row, not
/// the answer, says whether the member is still pending and which roles the
/// picks granted.
mixin _DiscordGuildJoinGate implements GuildJoinGateRepository {
  DiscordRestClient get _rest;

  Future<Member?> _readOwnMembership(String guildId);

  /// `GET /guilds/{id}/member-verification`. Discord answers 404 when the
  /// server screens nobody.
  @override
  Future<RulesScreening?> loadRulesScreening(String guildId) async {
    try {
      return _screening(
        await _rest.getObject(
          '/guilds/${_segment(guildId)}/member-verification',
        ),
      );
    } on DiscordApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// `PUT /guilds/{id}/requests/@me` with every field of [screening], the
  /// rules agreed to and the questions answered as [screening] holds them.
  @override
  Future<Member?> acceptRules({
    required String guildId,
    required RulesScreening screening,
  }) async {
    await _refusedWith(
      'Discord did not accept the rules',
      () => _rest.requestObject(
        'PUT',
        '/guilds/${_segment(guildId)}/requests/@me',
        body: {
          'version': screening.version,
          'form_fields': [
            for (final field in screening.fields)
              {
                'field_type': field.type,
                'label': field.label,
                'required': field.required,
                'description': field.description,
                if (field.rules.isNotEmpty) 'values': field.rules,
                if (field.choices.isNotEmpty) 'choices': field.choices,
                'response': ?switch (field.answer) {
                  _ when field.isRules => true,
                  ScreeningText(:final text) => text.trim(),
                  ScreeningChoice(:final index) => index,
                  null => null,
                },
              },
          ],
        },
      ),
    );
    return _readOwnMembership(guildId);
  }

  /// `GET /guilds/{id}/onboarding`. A member may read it only while it is
  /// enabled; a refusal means there is nothing to walk through.
  @override
  Future<GuildOnboarding?> loadOnboarding(String guildId) async {
    final Map<String, Object?> payload;
    try {
      payload = await _rest.getObject(
        '/guilds/${_segment(guildId)}/onboarding',
      );
    } on DiscordApiException catch (error) {
      if (error.isForbidden || error.statusCode == 404) return null;
      rethrow;
    }
    if (payload['enabled'] != true) return null;
    final prompts = [
      for (final prompt in _maps(payload['prompts']))
        if (prompt['in_onboarding'] != false) _prompt(prompt),
    ];
    if (prompts.isEmpty) return null;
    return GuildOnboarding(
      guildId: guildId,
      prompts: prompts,
      defaultChannelIds: _strings(payload['default_channel_ids']),
    );
  }

  /// `PUT /guilds/{id}/onboarding-responses`.
  @override
  Future<Member?> answerOnboarding({
    required String guildId,
    required GuildOnboarding onboarding,
    required Set<String> chosenOptionIds,
    required DateTime seenAt,
  }) async {
    final seen = seenAt.millisecondsSinceEpoch;
    await _refusedWith(
      'Discord did not save your answers',
      () => _rest.requestEmpty(
        'PUT',
        '/guilds/${_segment(guildId)}/onboarding-responses',
        body: {
          'onboarding_responses': chosenOptionIds.toList(growable: false),
          'onboarding_prompts_seen': {
            for (final prompt in onboarding.prompts) prompt.id: seen,
          },
          'onboarding_responses_seen': {
            for (final prompt in onboarding.prompts)
              for (final option in prompt.options) option.id: seen,
          },
        },
      ),
    );
    return _readOwnMembership(guildId);
  }

  /// Runs [send], turning a refusal Discord explains into a
  /// [GuildJoinGateRefusal] that starts with [lead].
  static Future<void> _refusedWith(
    String lead,
    Future<Object?> Function() send,
  ) async {
    try {
      await send();
    } on DiscordApiException catch (error) {
      if (error.statusCode < 400 || error.statusCode >= 500) rethrow;
      throw GuildJoinGateRefusal('$lead: ${error.message}');
    }
  }

  static RulesScreening _screening(Map<String, Object?> payload) =>
      RulesScreening(
        version: payload['version'] as String?,
        description: _text(payload['description']),
        fields: [
          for (final field in _maps(payload['form_fields']))
            RulesScreeningField(
              type: field['field_type'] as String? ?? '',
              label: field['label'] as String? ?? '',
              required: field['required'] == true,
              rules: _strings(field['values']),
              choices: _strings(field['choices']),
              description: _text(field['description']),
              placeholder: _text(field['placeholder']),
            ),
        ],
      );

  static OnboardingPrompt _prompt(Map<String, Object?> payload) =>
      OnboardingPrompt(
        id: payload['id'] as String? ?? '',
        title: payload['title'] as String? ?? '',
        singleSelect: payload['single_select'] == true,
        required: payload['required'] == true,
        options: [
          for (final option in _maps(payload['options']))
            OnboardingOption(
              id: option['id'] as String? ?? '',
              title: option['title'] as String? ?? '',
              description: _text(option['description']),
              emoji: switch (option['emoji']) {
                {'id': null, 'name': final String name} when name.isNotEmpty =>
                  name,
                _ => null,
              },
              channelIds: _strings(option['channel_ids']),
              roleIds: _strings(option['role_ids']),
            ),
        ],
      );

  static List<Map<String, Object?>> _maps(Object? raw) => [
    if (raw is List)
      for (final item in raw)
        if (item is Map) item.cast<String, Object?>(),
  ];

  static List<String> _strings(Object? raw) =>
      raw is List ? raw.whereType<String>().toList(growable: false) : const [];

  /// [raw] as text, with an empty string read as none.
  static String? _text(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;
}
