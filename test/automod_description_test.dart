import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/guild_automod_rule_dialog.dart';
import 'package:flucord/src/presentation/widgets/guild_settings_automod_section.dart';
import 'package:flutter_test/flutter_test.dart';

AutoModRule _rule({
  AutoModTriggerType trigger = AutoModTriggerType.keyword,
  AutoModTriggerMetadata metadata = const AutoModTriggerMetadata(),
  List<AutoModAction> actions = const [],
}) => AutoModRule(
  id: 'rule-1',
  guildId: 'guild-1',
  name: 'A rule',
  eventType: AutoModEventType.messageSend,
  triggerType: trigger,
  metadata: metadata,
  actions: actions,
);

final _workspace = ChatWorkspace(
  spaces: const [],
  channels: const [
    ConversationChannel(
      id: 'channel-1',
      spaceId: 'guild-1',
      name: 'alerts',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: const [],
  messages: const [],
  currentMemberId: 'member-1',
);

void main() {
  group('what a rule watches', () {
    test('a word rule counts what it holds', () {
      expect(
        describeAutoModRule(
          _rule(metadata: const AutoModTriggerMetadata(keywordFilter: ['a'])),
        ),
        '1 word — no action',
      );
      expect(
        describeAutoModRule(
          _rule(
            metadata: const AutoModTriggerMetadata(
              keywordFilter: ['a', 'b'],
              regexPatterns: ['^c'],
            ),
          ),
        ),
        '2 words and 1 pattern — no action',
      );
      expect(
        describeAutoModRule(
          _rule(
            metadata: const AutoModTriggerMetadata(regexPatterns: ['^a', '^b']),
          ),
        ),
        '2 patterns — no action',
      );
      // A rule created and then emptied still has to say something.
      expect(describeAutoModRule(_rule()), 'Nothing yet — no action');
    });

    test('every other trigger says what it is', () {
      expect(
        describeAutoModRule(_rule(trigger: AutoModTriggerType.spamLink)),
        startsWith('Suspicious links'),
      );
      expect(
        describeAutoModRule(_rule(trigger: AutoModTriggerType.mlSpam)),
        startsWith('Spam Discord detects'),
      );
      expect(
        describeAutoModRule(
          _rule(trigger: AutoModTriggerType.defaultKeywordList),
        ),
        startsWith("Discord's word lists"),
      );
      expect(
        describeAutoModRule(
          _rule(
            trigger: AutoModTriggerType.mentionSpam,
            metadata: const AutoModTriggerMetadata(mentionTotalLimit: 5),
          ),
        ),
        startsWith('Over 5 mentions'),
      );
      expect(
        describeAutoModRule(_rule(trigger: AutoModTriggerType.serverPolicy)),
        startsWith('Server policy'),
      );
      expect(
        describeAutoModRule(_rule(trigger: AutoModTriggerType.userProfile)),
        startsWith('Nothing yet'),
      );
      expect(
        describeAutoModRule(_rule(trigger: AutoModTriggerType.unknown)),
        startsWith('A rule this build does not know'),
      );
    });
  });

  group('what a rule does', () {
    test('each consequence is named, in the order they happen', () {
      expect(
        describeAutoModRule(
          _rule(
            metadata: const AutoModTriggerMetadata(keywordFilter: ['a']),
            actions: const [
              AutoModAction(type: AutoModActionType.blockMessage),
              AutoModAction(
                type: AutoModActionType.flagToChannel,
                channelId: 'channel-1',
              ),
              AutoModAction(
                type: AutoModActionType.userCommunicationDisabled,
                durationSeconds: 3600,
              ),
            ],
          ),
          workspace: _workspace,
        ),
        '1 word — blocks the message, alerts #alerts, times out for 1 hour',
      );
    });

    test('a timeout is stated in the largest unit that fits', () {
      String describe(int seconds) => describeAutoModRule(
        _rule(
          actions: [
            AutoModAction(
              type: AutoModActionType.userCommunicationDisabled,
              durationSeconds: seconds,
            ),
          ],
        ),
      );

      expect(describe(60), endsWith('times out for 1 minute'));
      expect(describe(120), endsWith('times out for 2 minutes'));
      expect(describe(3600), endsWith('times out for 1 hour'));
      expect(describe(7200), endsWith('times out for 2 hours'));
      expect(describe(86400), endsWith('times out for 1 day'));
      expect(describe(172800), endsWith('times out for 2 days'));
    });

    test('a channel nothing knows about is still named as one', () {
      // The alert channel can be one this account cannot see, and a rule that
      // read "alerts " with nothing after it would look broken.
      expect(
        describeAutoModRule(
          _rule(
            actions: const [
              AutoModAction(
                type: AutoModActionType.flagToChannel,
                channelId: 'channel-9',
              ),
            ],
          ),
          workspace: _workspace,
        ),
        endsWith('alerts a channel'),
      );
      expect(
        describeAutoModRule(
          _rule(
            actions: const [
              AutoModAction(
                type: AutoModActionType.flagToChannel,
                channelId: 'channel-1',
              ),
            ],
          ),
        ),
        endsWith('alerts a channel'),
      );
    });
  });

  test('every trigger has a name the page can show', () {
    for (final trigger in AutoModTriggerType.values) {
      expect(autoModTriggerLabel(trigger), isNotEmpty, reason: trigger.name);
    }
    expect(autoModTriggerLabel(AutoModTriggerType.keyword), 'Custom words');
    expect(autoModTriggerLabel(AutoModTriggerType.unknown), 'Unsupported');
  });
}
