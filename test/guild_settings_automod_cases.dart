part of 'guild_settings_controller_test.dart';

void _automodControllerCases() {
  group('automod', () {
    test('the page loads on open and is gated on Manage Server', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);

      expect(
        controller.availableSections,
        contains(GuildSettingsSection.automod),
      );
      await controller.openSection(GuildSettingsSection.automod);

      expect(repository.calls, ['loadAutoModRules']);
      expect(controller.automodRules.single.name, 'No invites');
      expect(controller.canEditAutoMod, isTrue);
    });

    test(
      'an account without Manage Server sees no page and no writes',
      () async {
        final repository = FakeGuildManagementRepository();
        final controller = _controller(
          repository: repository,
          permissions: DiscordPermissions.combine([
            DiscordPermissions.viewChannel,
            DiscordPermissions.banMembers,
          ]),
        );

        expect(
          controller.availableSections,
          isNot(contains(GuildSettingsSection.automod)),
        );
        expect(controller.canEditAutoMod, isFalse);
        expect(await controller.createAutoModRule(_draft()), isFalse);
        expect(
          await controller.updateAutoModRule('rule-1', _enable()),
          isFalse,
        );
        expect(await controller.deleteAutoModRule('rule-1'), isFalse);
        expect(await controller.clearMentionRaid(), isFalse);
        expect(await controller.reportMentionRaidFalseAlarm(), isFalse);
        expect(await controller.validateAutoModDraft(_draft()), isNull);
        expect(repository.calls, isEmpty);
      },
    );

    test('a created rule joins the list without a refetch', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.automod);

      expect(await controller.createAutoModRule(_draft()), isTrue);

      expect(repository.calls, ['loadAutoModRules', 'createAutoModRule']);
      expect(controller.automodRules, hasLength(2));
      expect(controller.automodRules.last.name, 'No links');
    });

    test('a draft the server would refuse is never sent', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);

      expect(
        await controller.createAutoModRule(
          const AutoModRuleDraft(
            name: '',
            eventType: AutoModEventType.messageSend,
            triggerType: AutoModTriggerType.keyword,
            actions: [],
          ),
        ),
        isFalse,
      );
      expect(repository.calls, isEmpty);
    });

    test('an edit replaces the row it changed and nothing else', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.automod);

      expect(
        await controller.setAutoModRuleEnabled('rule-1', enabled: false),
        isTrue,
      );

      expect(repository.lastAutoModEdit?['enabled'], isFalse);
      expect(controller.automodRules.single.enabled, isFalse);
      // The name came back untouched, so nothing else was rewritten.
      expect(controller.automodRules.single.name, 'No invites');
    });

    test('an empty edit is not a request', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);

      expect(
        await controller.updateAutoModRule('rule-1', AutoModRuleEdit()),
        isFalse,
      );
      expect(repository.calls, isEmpty);
    });

    test('a deleted rule leaves the list', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.automod);

      expect(await controller.deleteAutoModRule('rule-1'), isTrue);

      expect(controller.automodRules, isEmpty);
    });

    test('a failed write is reported and the list is left alone', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.automod);
      repository.failNext = true;

      expect(await controller.deleteAutoModRule('rule-1'), isFalse);

      expect(controller.actionError, isA<StateError>());
      expect(controller.automodRules, hasLength(1));
    });

    test('validation answers the server, and silence when it cannot', () async {
      final repository = FakeGuildManagementRepository()
        ..validationFailure = 'Invalid regex';
      final controller = _controller(repository: repository);

      expect(await controller.validateAutoModDraft(_draft()), 'Invalid regex');

      repository
        ..validationFailure = null
        ..failNext = true;
      // A validation that could not be asked answers "no opinion" rather than
      // refusing a rule that may well be correct.
      expect(await controller.validateAutoModDraft(_draft()), isNull);
      expect(controller.actionError, isNull);
    });

    test('a trigger already spent is not offered again', () async {
      final controller = _controller();
      await controller.openSection(GuildSettingsSection.automod);

      final triggers = controller.availableAutoModTriggers;

      // The fixture holds a keyword rule, and a guild may have many of those.
      expect(triggers, contains(AutoModTriggerType.keyword));
      expect(triggers, isNot(contains(AutoModTriggerType.unknown)));

      await controller.createAutoModRule(
        _draft(trigger: AutoModTriggerType.mlSpam),
      );

      expect(
        controller.availableAutoModTriggers,
        isNot(contains(AutoModTriggerType.mlSpam)),
      );
    });

    test('the raid controls reach their routes', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);

      expect(await controller.clearMentionRaid(), isTrue);
      expect(await controller.reportMentionRaidFalseAlarm(), isTrue);

      expect(repository.calls, [
        'clearMentionRaid',
        'reportMentionRaidFalseAlarm',
      ]);
    });
  });
}

AutoModRuleDraft _draft({
  AutoModTriggerType trigger = AutoModTriggerType.keyword,
}) => AutoModRuleDraft(
  name: 'No links',
  eventType: AutoModEventType.messageSend,
  triggerType: trigger,
  metadata: const AutoModTriggerMetadata(keywordFilter: ['http']),
  actions: const [AutoModAction(type: AutoModActionType.blockMessage)],
);

AutoModRuleEdit _enable() => AutoModRuleEdit()..enabled = true;
