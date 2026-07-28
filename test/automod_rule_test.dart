import 'package:flucord/src/data/discord/discord_automod_mapper.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/automod_rule_editing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _rulePayload({
  Object? id = 'rule-1',
  int trigger = 1,
  int event = 1,
  Object? enabled,
  Object? metadata,
  Object? actions,
}) => {
  'id': id,
  'guild_id': 'guild-1',
  'name': 'No invites',
  'creator_id': 'mod-1',
  'event_type': event,
  'trigger_type': trigger,
  'enabled': ?enabled,
  'trigger_metadata':
      metadata ??
      {
        'keyword_filter': ['discord.gg/*', 7],
        'regex_patterns': ['^spam'],
        'presets': [1, 3, 99],
        'allow_list': ['discord.gg/flucord'],
        'mention_total_limit': '12',
        'mention_raid_protection_enabled': true,
      },
  'actions':
      actions ??
      [
        {'type': 1, 'metadata': <String, Object?>{}},
        {
          'type': 2,
          'metadata': {'channel_id': 'channel-1', 'custom_message': 'no'},
        },
        {
          'type': 3,
          'metadata': {'duration_seconds': 3600},
        },
      ],
  'exempt_roles': ['role-1', 8],
  'exempt_channels': ['channel-9'],
};

void main() {
  group('mapping', () {
    test('reads a rule as the server states it', () {
      final rule = DiscordAutoModMapper.rule(_rulePayload())!;

      expect(rule.id, 'rule-1');
      expect(rule.guildId, 'guild-1');
      expect(rule.creatorId, 'mod-1');
      expect(rule.eventType, AutoModEventType.messageSend);
      expect(rule.triggerType, AutoModTriggerType.keyword);
      // A rule that has never been switched off arrives without the flag.
      expect(rule.enabled, isTrue);
      // Non-strings in a string list are dropped rather than stringified.
      expect(rule.metadata.keywordFilter, ['discord.gg/*']);
      expect(rule.metadata.regexPatterns, ['^spam']);
      expect(rule.metadata.presets, [
        AutoModKeywordPreset.profanity,
        AutoModKeywordPreset.slurs,
        AutoModKeywordPreset.unknown,
      ]);
      expect(rule.metadata.allowList, ['discord.gg/flucord']);
      // Discord sends numbers as strings on some routes.
      expect(rule.metadata.mentionTotalLimit, 12);
      expect(rule.metadata.mentionRaidProtectionEnabled, isTrue);
      expect(rule.exemptRoleIds, ['role-1']);
      expect(rule.exemptChannelIds, ['channel-9']);
      expect(rule.blocksMessages, isTrue);
      expect(rule.alertChannelId, 'channel-1');
      expect(rule.timeout, const Duration(hours: 1));
      expect(rule.actions.first.customMessage, isEmpty);
      expect(rule.actions[1].customMessage, 'no');
    });

    test('a rule with no id is not a rule', () {
      expect(DiscordAutoModMapper.rule(_rulePayload(id: null)), isNull);
      expect(DiscordAutoModMapper.rule(_rulePayload(id: '')), isNull);
      expect(DiscordAutoModMapper.rule(const {}), isNull);
    });

    test('an explicit disable survives', () {
      final rule = DiscordAutoModMapper.rule(_rulePayload(enabled: false))!;

      expect(rule.enabled, isFalse);
    });

    test('a trigger this build predates reads as unknown, not as a crash', () {
      final rule = DiscordAutoModMapper.rule(
        _rulePayload(
          trigger: 42,
          event: 42,
          actions: [
            {'type': 99, 'metadata': null},
          ],
        ),
      )!;

      expect(rule.triggerType, AutoModTriggerType.unknown);
      expect(rule.eventType, AutoModEventType.unknown);
      expect(rule.actions.single.type, AutoModActionType.unknown);
      expect(rule.actions.single.channelId, isEmpty);
      // No alert action and no timeout action means neither is claimed.
      expect(rule.alertChannelId, isEmpty);
      expect(rule.timeout, Duration.zero);
      expect(rule.blocksMessages, isFalse);
    });

    test('nonsense where an object was expected reads as empty', () {
      expect(DiscordAutoModMapper.metadata('nonsense').isEmpty, isTrue);
      expect(DiscordAutoModMapper.metadata(null).isEmpty, isTrue);
      expect(DiscordAutoModMapper.actions('nonsense'), isEmpty);
      final rule = DiscordAutoModMapper.rule(
        _rulePayload(metadata: 'nonsense', actions: 'nonsense'),
      )!;
      expect(rule.metadata.isEmpty, isTrue);
      expect(rule.actions, isEmpty);
    });

    test('a list reads every rule it holds and skips what is not one', () {
      final rules = DiscordAutoModMapper.rules([
        _rulePayload(),
        'nonsense',
        _rulePayload(id: null),
        {'id': 'rule-2', 'name': 'Second'},
      ], guildId: 'guild-2');

      expect(rules.map((rule) => rule.id), ['rule-1', 'rule-2']);
      // The guild is taken from the payload when it names one, and from the
      // request when it does not.
      expect(rules.first.guildId, 'guild-1');
      expect(rules.last.guildId, 'guild-2');
      expect(DiscordAutoModMapper.rules(null), isEmpty);
    });
  });

  group('drafts', () {
    const blocking = [AutoModAction(type: AutoModActionType.blockMessage)];

    AutoModRuleDraft draft({
      String name = 'Rule',
      AutoModTriggerType trigger = AutoModTriggerType.keyword,
      AutoModEventType event = AutoModEventType.messageSend,
      AutoModTriggerMetadata metadata = const AutoModTriggerMetadata(
        keywordFilter: ['a'],
      ),
      List<AutoModAction> actions = blocking,
    }) => AutoModRuleDraft(
      name: name,
      eventType: event,
      triggerType: trigger,
      metadata: metadata,
      actions: actions,
    );

    test('a rule needs a name, an action and something to match', () {
      expect(draft().isValid, isTrue);
      expect(draft(name: '   ').isValid, isFalse);
      expect(draft(actions: const []).isValid, isFalse);
      expect(draft(event: AutoModEventType.unknown).isValid, isFalse);
      expect(draft(trigger: AutoModTriggerType.unknown).isValid, isFalse);
    });

    test('what counts as something to match depends on the trigger', () {
      expect(draft(metadata: const AutoModTriggerMetadata()).isValid, isFalse);
      expect(
        draft(
          metadata: const AutoModTriggerMetadata(regexPatterns: ['^a']),
        ).isValid,
        isTrue,
      );
      expect(
        draft(
          trigger: AutoModTriggerType.userProfile,
          event: AutoModEventType.guildMemberJoinOrUpdate,
          metadata: const AutoModTriggerMetadata(),
        ).isValid,
        isFalse,
      );
      expect(
        draft(
          trigger: AutoModTriggerType.defaultKeywordList,
          metadata: const AutoModTriggerMetadata(),
        ).isValid,
        isFalse,
      );
      expect(
        draft(
          trigger: AutoModTriggerType.defaultKeywordList,
          metadata: const AutoModTriggerMetadata(
            presets: [AutoModKeywordPreset.slurs],
          ),
        ).isValid,
        isTrue,
      );
      expect(
        draft(
          trigger: AutoModTriggerType.mentionSpam,
          metadata: const AutoModTriggerMetadata(),
        ).isValid,
        isFalse,
      );
      expect(
        draft(
          trigger: AutoModTriggerType.mentionSpam,
          metadata: const AutoModTriggerMetadata(mentionTotalLimit: 5),
        ).isValid,
        isTrue,
      );
      // A trigger with nothing to configure needs nothing configured.
      expect(
        draft(
          trigger: AutoModTriggerType.mlSpam,
          metadata: const AutoModTriggerMetadata(),
        ).isValid,
        isTrue,
      );
    });

    test('a create sends every field, present or empty', () {
      final body = AutoModRuleEdit.encodeDraft(
        draft(
          metadata: const AutoModTriggerMetadata(
            keywordFilter: ['a'],
            presets: [AutoModKeywordPreset.profanity],
            allowList: ['b'],
            mentionTotalLimit: 4,
            mentionRaidProtectionEnabled: true,
            regexPatterns: ['^c'],
          ),
          actions: const [
            AutoModAction(type: AutoModActionType.blockMessage),
            AutoModAction(
              type: AutoModActionType.flagToChannel,
              channelId: 'channel-1',
              customMessage: 'no',
            ),
            AutoModAction(
              type: AutoModActionType.userCommunicationDisabled,
              durationSeconds: 60,
            ),
          ],
        ),
      );

      expect(body['name'], 'Rule');
      expect(body['event_type'], 1);
      expect(body['trigger_type'], 1);
      expect(body['enabled'], isTrue);
      expect(body['exempt_roles'], isEmpty);
      expect(body['trigger_metadata'], {
        'keyword_filter': ['a'],
        'regex_patterns': ['^c'],
        'presets': [1],
        'allow_list': ['b'],
        'mention_total_limit': 4,
        'mention_raid_protection_enabled': true,
      });
      expect(body['actions'], [
        {'type': 1, 'metadata': <String, Object?>{}},
        {
          'type': 2,
          'metadata': {'channel_id': 'channel-1', 'custom_message': 'no'},
        },
        {
          'type': 3,
          'metadata': {'duration_seconds': 60},
        },
      ]);
    });

    test('an empty metadata sends an empty object rather than nulls', () {
      expect(
        AutoModRuleEdit.encodeMetadata(const AutoModTriggerMetadata()),
        isEmpty,
      );
    });
  });

  group('edits', () {
    test('only what was touched is sent', () {
      final edit = AutoModRuleEdit();

      expect(edit.isEmpty, isTrue);
      expect(edit.isNotEmpty, isFalse);

      edit
        ..name = 'Renamed'
        ..enabled = false
        ..eventType = AutoModEventType.guildMemberJoinOrUpdate
        ..metadata = const AutoModTriggerMetadata(keywordFilter: ['a'])
        ..actions = const [AutoModAction(type: AutoModActionType.blockMessage)]
        ..exemptRoleIds = ['role-1']
        ..exemptChannelIds = ['channel-1'];

      expect(edit.isNotEmpty, isTrue);
      expect(edit['name'], 'Renamed');
      expect(edit['enabled'], isFalse);
      expect(edit['event_type'], 2);
      expect(edit['trigger_metadata'], {
        'keyword_filter': ['a'],
      });
      expect(edit['actions'], [
        {'type': 1, 'metadata': <String, Object?>{}},
      ]);
      expect(edit['exempt_roles'], ['role-1']);
      expect(edit['exempt_channels'], ['channel-1']);
      expect(edit.keys, hasLength(7));
      expect(edit.toJson()['name'], 'Renamed');
    });
  });

  group('the model', () {
    test('a trigger knows whether a guild may hold more than one', () {
      expect(AutoModTriggerType.keyword.allowsMany, isTrue);
      expect(AutoModTriggerType.userProfile.allowsMany, isTrue);
      expect(AutoModTriggerType.mlSpam.allowsMany, isFalse);
      expect(AutoModTriggerType.keyword.hasKeywords, isTrue);
      expect(AutoModTriggerType.mentionSpam.hasKeywords, isFalse);
    });

    test('metadata and actions compare by what they say', () {
      const metadata = AutoModTriggerMetadata(
        keywordFilter: ['a'],
        presets: [AutoModKeywordPreset.slurs],
      );

      expect(
        metadata,
        const AutoModTriggerMetadata(
          keywordFilter: ['a'],
          presets: [AutoModKeywordPreset.slurs],
        ),
      );
      expect(
        metadata.hashCode,
        const AutoModTriggerMetadata(
          keywordFilter: ['a'],
          presets: [AutoModKeywordPreset.slurs],
        ).hashCode,
      );
      expect(
        metadata == const AutoModTriggerMetadata(keywordFilter: ['b']),
        isFalse,
      );
      expect(
        metadata == const AutoModTriggerMetadata(keywordFilter: ['a', 'b']),
        isFalse,
      );
      expect(
        const AutoModTriggerMetadata(keywordFilter: ['a']) ==
            const AutoModTriggerMetadata(
              keywordFilter: ['a'],
              presets: [AutoModKeywordPreset.slurs],
            ),
        isFalse,
      );
      expect(
        const AutoModTriggerMetadata(
              keywordFilter: ['a'],
              presets: [AutoModKeywordPreset.slurs],
            ) ==
            const AutoModTriggerMetadata(
              keywordFilter: ['a'],
              presets: [AutoModKeywordPreset.profanity],
            ),
        isFalse,
      );
      expect(
        const AutoModTriggerMetadata(mentionTotalLimit: 1) ==
            const AutoModTriggerMetadata(mentionTotalLimit: 2),
        isFalse,
      );
      expect(metadata == Object(), isFalse);

      const action = AutoModAction(type: AutoModActionType.blockMessage);
      expect(action, const AutoModAction(type: AutoModActionType.blockMessage));
      expect(
        action.hashCode,
        const AutoModAction(type: AutoModActionType.blockMessage).hashCode,
      );
      expect(
        action == const AutoModAction(type: AutoModActionType.quarantineUser),
        isFalse,
      );
      expect(action == Object(), isFalse);
      expect(AutoModAction.maxTimeout, const Duration(days: 28));
    });
  });
}
