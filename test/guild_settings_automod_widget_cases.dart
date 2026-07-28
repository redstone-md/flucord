part of 'guild_settings_widget_test.dart';

void _automodWidgetCases() {
  testWidgets('the page lists each rule and what it does', (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    expect(find.byKey(const ValueKey('automod-rule-rule-1')), findsOneWidget);
    expect(find.text('No invites'), findsOneWidget);
    expect(find.text('1 word — blocks the message'), findsOneWidget);

    harness.dispose();
  });

  testWidgets('the switch turns a rule off without deleting it', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-enabled-rule-1')));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, contains('updateAutoModRule'));
    expect(harness.repository.lastAutoModEdit?['enabled'], isFalse);
    expect(harness.controller.automodRules, hasLength(1));

    harness.dispose();
  });

  testWidgets('delete removes the row', (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-delete-rule-1')));
    await tester.pumpAndSettle();

    expect(harness.controller.automodRules, isEmpty);
    expect(find.text('No rules are set up here.'), findsOneWidget);

    harness.dispose();
  });

  testWidgets('the create dialog sends a draft the server would take', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-create-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('automod-rule-dialog')), findsOneWidget);
    // Nothing to save until the rule has a name and something to match.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('automod-save')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('automod-name')),
      'No links',
    );
    await tester.enterText(
      find.byKey(const ValueKey('automod-keywords')),
      'http, , https',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, contains('createAutoModRule'));
    final created = harness.controller.automodRules.last;
    expect(created.name, 'No links');
    // The blank between the commas is dropped rather than sent as a word that
    // would match everything.
    expect(created.metadata.keywordFilter, ['http', 'https']);
    expect(created.blocksMessages, isTrue);

    harness.dispose();
  });

  testWidgets('the check button reports the server verdict', (tester) async {
    final harness = await _pump(tester);
    harness.repository.validationFailure = 'Invalid regex';
    await _openAutoMod(tester);
    await tester.tap(find.byKey(const ValueKey('automod-create-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('automod-check')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid regex'), findsOneWidget);

    harness.repository.validationFailure = null;
    await tester.tap(find.byKey(const ValueKey('automod-check')));
    await tester.pumpAndSettle();

    expect(find.text('The server would accept this rule.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    harness.dispose();
  });

  testWidgets('editing offers no trigger to change and sends only the diff', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-edit-rule-1')));
    await tester.pumpAndSettle();

    // The trigger is fixed on an existing rule: Discord refuses to change it.
    expect(find.byKey(const ValueKey('automod-trigger')), findsNothing);
    expect(find.text('Trigger: Custom words'), findsOneWidget);
    // A check would be about a create; an edit has nothing to validate.
    expect(find.byKey(const ValueKey('automod-check')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('automod-name')),
      'Renamed',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.lastAutoModEdit?['name'], 'Renamed');
    // Only the name moved, so nothing else was sent.
    expect(harness.repository.lastAutoModEdit?.keys, ['name']);
    expect(harness.controller.automodRules.single.name, 'Renamed');

    harness.dispose();
  });

  testWidgets('an edit that changed nothing sends nothing', (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-edit-rule-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, isNot(contains('updateAutoModRule')));

    harness.dispose();
  });

  testWidgets('the raid controls are on the page', (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-clear-raid')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-false-alarm')));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, contains('clearMentionRaid'));
    expect(harness.repository.calls, contains('reportMentionRaidFalseAlarm'));

    harness.dispose();
  });
}

Future<void> _openAutoMod(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('guild-settings-rail-automod')).first,
  );
  await tester.pumpAndSettle();
}

void _automodDialogCases() {
  testWidgets('a mention-spam rule asks for the limit and sends it', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);
    await tester.tap(find.byKey(const ValueKey('automod-create-open')));
    await tester.pumpAndSettle();

    // A keyword rule is offered first, so the limit is not asked for yet.
    expect(find.byKey(const ValueKey('automod-mention-limit')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('automod-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mention spam').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('automod-keywords')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('automod-name')),
      'Mention limit',
    );
    await tester.enterText(
      find.byKey(const ValueKey('automod-mention-limit')),
      '5',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    final created = harness.controller.automodRules.last;
    expect(created.triggerType, AutoModTriggerType.mentionSpam);
    expect(created.metadata.mentionTotalLimit, 5);
    // A mention rule carries no words even though the fields once held some.
    expect(created.metadata.keywordFilter, isEmpty);

    harness.dispose();
  });

  testWidgets('the alert channel and timeout become actions', (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);
    await tester.tap(find.byKey(const ValueKey('automod-create-open')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('automod-name')),
      'Loud words',
    );
    await tester.enterText(
      find.byKey(const ValueKey('automod-keywords')),
      'shout',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('automod-alert-channel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#general').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('automod-timeout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 hour').last);
    await tester.pumpAndSettle();

    // Blocking is on by default; turning it off proves the switch is read.
    await tester.tap(find.byKey(const ValueKey('automod-block')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    final created = harness.controller.automodRules.last;
    expect(created.blocksMessages, isFalse);
    expect(created.alertChannelId, isNotEmpty);
    expect(created.timeout, const Duration(hours: 1));

    harness.dispose();
  });

  testWidgets('an existing rule opens with what it already holds', (
    tester,
  ) async {
    final harness = await _pump(tester);
    harness.repository.automodRules['rule-2'] = const AutoModRule(
      id: 'rule-2',
      guildId: guildId,
      name: 'Mention guard',
      eventType: AutoModEventType.messageSend,
      triggerType: AutoModTriggerType.mentionSpam,
      metadata: AutoModTriggerMetadata(mentionTotalLimit: 7),
      actions: [AutoModAction(type: AutoModActionType.blockMessage)],
      enabled: true,
    );
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-edit-rule-2')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('automod-mention-limit')),
          )
          .controller
          ?.text,
      '7',
    );

    // Raising the limit is a metadata change, which the edit has to carry.
    await tester.enterText(
      find.byKey(const ValueKey('automod-mention-limit')),
      '9',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.lastAutoModEdit?['trigger_metadata'], {
      'mention_total_limit': 9,
    });

    harness.dispose();
  });

  testWidgets('changing what a rule does sends the new actions', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-edit-rule-1')));
    await tester.pumpAndSettle();

    // The seeded rule only blocks; adding a timeout is an action change.
    await tester.tap(find.byKey(const ValueKey('automod-timeout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 day').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.lastAutoModEdit?.keys, ['actions']);
    expect(harness.repository.lastAutoModEdit?['actions'], [
      {'type': 1, 'metadata': <String, Object?>{}},
      {
        'type': 3,
        'metadata': {'duration_seconds': 86400},
      },
    ]);

    harness.dispose();
  });

  testWidgets("a preset rule picks from Discord's lists", (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);
    await tester.tap(find.byKey(const ValueKey('automod-create-open')));
    await tester.pumpAndSettle();

    // A word rule has no presets to pick; a preset rule has nothing to type.
    expect(
      find.byKey(const ValueKey('automod-preset-profanity')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('automod-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Discord's word lists").last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('automod-keywords')), findsNothing);
    // The unknown member is a round-trip placeholder, never an option.
    expect(find.byKey(const ValueKey('automod-preset-unknown')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('automod-name')),
      'House rules',
    );
    await tester.pumpAndSettle();
    // Nothing to save until at least one list is on.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('automod-save')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('automod-preset-slurs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-preset-profanity')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('automod-allow-list')),
      'damn',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    final created = harness.controller.automodRules.last;
    expect(created.triggerType, AutoModTriggerType.defaultKeywordList);
    expect(created.metadata.presets, [
      AutoModKeywordPreset.profanity,
      AutoModKeywordPreset.slurs,
    ]);
    expect(created.metadata.allowList, ['damn']);

    harness.dispose();
  });

  testWidgets('a preset can be turned back off', (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);
    await tester.tap(find.byKey(const ValueKey('automod-create-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Discord's word lists").last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('automod-preset-slurs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-preset-slurs')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('automod-save')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    harness.dispose();
  });

  testWidgets('exemptions are chosen and sent as whole lists', (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-edit-rule-1')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('automod-exempt-role-moderator')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('automod-exempt-channel-$textChannelId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    final edit = harness.repository.lastAutoModEdit;
    expect(edit?['exempt_roles'], ['moderator']);
    expect(edit?['exempt_channels'], [textChannelId]);
    // Nothing else moved, so nothing else was sent.
    expect(edit?.keys, ['exempt_roles', 'exempt_channels']);

    harness.dispose();
  });

  testWidgets('an exemption already held is offered as held', (tester) async {
    final harness = await _pump(tester);
    harness.repository.automodRules['rule-3'] = AutoModRule(
      id: 'rule-3',
      guildId: guildId,
      name: 'Exempt already',
      eventType: AutoModEventType.messageSend,
      triggerType: AutoModTriggerType.keyword,
      metadata: const AutoModTriggerMetadata(keywordFilter: ['a']),
      actions: const [AutoModAction(type: AutoModActionType.blockMessage)],
      exemptRoleIds: const ['moderator'],
      exemptChannelIds: [textChannelId],
    );
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-edit-rule-3')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('automod-exempt-role-moderator')),
          )
          .selected,
      isTrue,
    );

    // Reopening and saving without touching anything sends nothing, so the
    // order the server listed the exemptions in is not read as a change.
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, isNot(contains('updateAutoModRule')));

    harness.dispose();
  });

  testWidgets('a preset rule opens with its lists already ticked', (
    tester,
  ) async {
    final harness = await _pump(tester);
    harness.repository.automodRules['rule-4'] = const AutoModRule(
      id: 'rule-4',
      guildId: guildId,
      name: 'House lists',
      eventType: AutoModEventType.messageSend,
      triggerType: AutoModTriggerType.defaultKeywordList,
      metadata: AutoModTriggerMetadata(
        // The unknown member stands for a preset newer than this build; it
        // must not come back as a tick nobody can see.
        presets: [AutoModKeywordPreset.slurs, AutoModKeywordPreset.unknown],
        allowList: ['heck'],
      ),
      actions: [AutoModAction(type: AutoModActionType.blockMessage)],
    );
    await _openAutoMod(tester);

    await tester.tap(find.byKey(const ValueKey('automod-edit-rule-4')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('automod-preset-slurs')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('automod-allow-list')))
          .controller
          ?.text,
      'heck',
    );

    await tester.tap(find.byKey(const ValueKey('automod-preset-profanity')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.lastAutoModEdit?['trigger_metadata'], {
      'presets': [1, 3],
      'allow_list': ['heck'],
    });

    harness.dispose();
  });

  testWidgets('a dialog dismissed changes nothing', (tester) async {
    final harness = await _pump(tester);
    await _openAutoMod(tester);
    await tester.tap(find.byKey(const ValueKey('automod-create-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, isNot(contains('createAutoModRule')));

    harness.dispose();
  });
}
