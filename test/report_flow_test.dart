import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/moderation_report.dart';

void main() {
  group('ReportElement validation', () {
    test('an optional element accepts anything', () {
      const element = ReportElement(type: ReportElementType.freeText);
      expect(element.accepts(null), isTrue);
      expect(element.accepts(''), isTrue);
    });

    test('a required element needs a non-blank value', () {
      const element = ReportElement(
        type: ReportElementType.freeText,
        required: true,
      );
      expect(element.accepts(null), isFalse);
      expect(element.accepts('   '), isFalse);
      expect(element.accepts('something'), isTrue);
    });

    test('a pattern is enforced when the server sent one', () {
      const element = ReportElement(
        type: ReportElementType.freeText,
        required: true,
        pattern: r'^\d{4}$',
      );
      expect(element.accepts('abcd'), isFalse);
      expect(element.accepts('1234'), isTrue);
    });

    test(
      'a pattern the server cannot compile is not the reporter\'s fault',
      () {
        const element = ReportElement(
          type: ReportElementType.freeText,
          required: true,
          pattern: '([',
        );
        expect(element.accepts('anything'), isTrue);
      },
    );

    test('an empty pattern is no pattern', () {
      const element = ReportElement(
        type: ReportElementType.freeText,
        required: true,
        pattern: '',
      );
      expect(element.accepts('x'), isTrue);
    });
  });

  group('ReportTarget', () {
    test('a message report names its channel and message', () {
      const target = MessageReportTarget(
        channelId: '222222222222222222',
        messageId: '333333333333333333',
      );
      expect(target.type, ReportType.message);
      expect(target.toEntityKeys(), {
        'channel_id': '222222222222222222',
        'message_id': '333333333333333333',
      });
    });

    test('a first DM has its own report type', () {
      const target = MessageReportTarget(
        channelId: '222222222222222222',
        messageId: '333333333333333333',
        isFirstDirectMessage: true,
      );
      expect(target.type, ReportType.firstDm);
      expect(target.type.wireName, 'first_dm');
    });

    test('a user report omits the guild when there is none', () {
      const outsideGuild = UserReportTarget(userId: '123456789012345678');
      expect(outsideGuild.toEntityKeys(), {'user_id': '123456789012345678'});
      const insideGuild = UserReportTarget(
        userId: '123456789012345678',
        guildId: '111111111111111111',
      );
      expect(insideGuild.toEntityKeys(), {
        'user_id': '123456789012345678',
        'guild_id': '111111111111111111',
      });
    });

    test('a guild report names only the guild', () {
      const target = GuildReportTarget('111111111111111111');
      expect(target.type, ReportType.guild);
      expect(target.toEntityKeys(), {'guild_id': '111111111111111111'});
    });
  });

  group('ReportFlow', () {
    test('walks to a child and records the step', () {
      final flow = _flow();
      expect(flow.currentNodeId, 'root');
      expect(flow.canGoBack, isFalse);
      expect(flow.currentNode!.header, 'Why?');
      expect(flow.choose(flow.currentNode!.choices.first), isTrue);
      expect(flow.currentNodeId, 'spam');
      expect(flow.breadcrumbs, ['root']);
      expect(flow.history.single.destinationNodeId, 'spam');
      expect(flow.history.single.destinationLabel, 'Spam');
      expect(flow.canGoBack, isTrue);
    });

    test('refuses a destination the menu never shipped', () {
      final flow = _flow();
      expect(
        flow.choose(const ReportChoice(label: 'Ghost', nodeId: 'nowhere')),
        isFalse,
      );
      expect(flow.currentNodeId, 'root');
      expect(flow.breadcrumbs, isEmpty);
    });

    test('a skip node forwards without entering the history', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Detour', nodeId: 'skipper'));
      expect(flow.currentNodeId, 'spam');
      expect(flow.history.single.destinationNodeId, 'spam');
    });

    test('a skip loop cannot hang the walker', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Loop', nodeId: 'loop-a'));
      expect(['loop-a', 'loop-b'], contains(flow.currentNodeId));
    });

    test('a skip node with no next button is entered normally', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Dead skip', nodeId: 'dead-skip'));
      expect(flow.currentNodeId, 'dead-skip');
    });

    test('the next button follows its target', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Other', nodeId: 'other'));
      expect(flow.advance(), isTrue);
      expect(flow.currentNodeId, 'spam');
    });

    test('a submit button is not a next button', () {
      final flow = _flow();
      flow.choose(flow.currentNode!.choices.first);
      expect(flow.advance(), isFalse);
    });

    test('going back restores what was typed', () {
      final flow = _flow();
      flow.setValue('note', 'first answer');
      flow.choose(flow.currentNode!.choices.first);
      expect(flow.valueOf('note'), isNull);
      expect(flow.goBack(), isTrue);
      expect(flow.currentNodeId, 'root');
      expect(flow.valueOf('note'), 'first answer');
      expect(flow.goBack(), isFalse);
    });

    test('checkbox defaults are applied on arrival', () {
      final flow = _flow();
      flow.choose(flow.currentNode!.choices.first);
      expect(flow.isChecked('scam'), isTrue);
      expect(flow.isChecked('unsolicited'), isFalse);
      flow.setChecked('unsolicited', checked: true);
      expect(flow.multiSelect, {'scam', 'unsolicited'});
      flow.setChecked('scam', checked: false);
      expect(flow.multiSelect, {'unsolicited'});
    });

    test('the submit gate follows the required elements', () {
      final flow = _flow();
      flow.choose(flow.currentNode!.choices.first);
      expect(flow.canAdvance, isFalse);
      flow.setValue('details', 'they kept messaging me');
      expect(flow.canAdvance, isTrue);
    });

    test('a required checkbox needs at least one key', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Pick', nodeId: 'pick'));
      expect(flow.canAdvance, isFalse);
      flow.setChecked('a', checked: true);
      expect(flow.canAdvance, isTrue);
    });

    test('a required content URL must parse', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Media', nodeId: 'media'));
      expect(flow.canAdvance, isFalse);
      flow.setValue('url', 'not a url');
      expect(flow.canAdvance, isFalse);
      flow.setValue('url', 'https://example.com/thing.png');
      expect(flow.canAdvance, isTrue);
    });

    test('a Discord CDN link also needs the message it came from', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Media', nodeId: 'media'));
      flow.setValue('url', 'https://cdn.discordapp.com/attachments/1/2/a.png');
      expect(flow.canAdvance, isFalse);
      flow.setValue('url_message_link', 'https://example.com/nope');
      expect(flow.canAdvance, isFalse);
      flow.setValue(
        'url_message_link',
        'https://discord.com/channels/111111111111111111/'
            '222222222222222222/333333333333333333',
      );
      expect(flow.canAdvance, isTrue);
    });

    test('a required element with no name cannot block the form', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Nameless', nodeId: 'nameless'));
      expect(flow.canAdvance, isTrue);
    });

    test('builds the submit body from the whole traversal', () {
      final flow = _flow();
      flow.setValue('note', 'context');
      flow.choose(flow.currentNode!.choices.first);
      flow.setValue('details', 'they kept messaging me');
      flow.setChecked('unsolicited', checked: true);
      final submission = flow.buildSubmission();
      expect(submission.type, ReportType.user);
      expect(submission.body['name'], 'user');
      expect(submission.body['version'], 7);
      expect(submission.body['variant'], 'staff');
      expect(submission.body['language'], 'en-GB');
      expect(submission.body['breadcrumbs'], ['root', 'spam']);
      expect(submission.body['user_id'], '123456789012345678');
      expect(submission.body['guild_id'], '111111111111111111');
      // Every other entity key is simply absent, which is what
      // `JSON.stringify` produces from the renderer's undefined-filled reset.
      expect(submission.body.containsKey('channel_id'), isFalse);
      final elements = submission.body['elements']! as Map<String, Object?>;
      expect(elements['note'], 'context');
      expect(elements['details'], 'they kept messaging me');
      expect(elements['reasons'], containsAll(['scam', 'unsolicited']));
    });

    test('a menu with no language defaults to English', () {
      final flow = ReportFlow(
        menu: _menu(language: null),
        target: const GuildReportTarget('111111111111111111'),
      );
      expect(flow.buildSubmission().body['language'], 'en');
    });

    test('a content URL writes both of its keys', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Media', nodeId: 'media'));
      flow.setValue('url', 'https://cdn.discordapp.com/attachments/1/2/a.png');
      flow.setValue('url_message_link', 'link');
      final elements =
          flow.buildSubmission().body['elements']! as Map<String, Object?>;
      expect(elements['url'], contains('cdn.discordapp.com'));
      expect(elements['url_message_link'], 'link');
    });

    test('an auto-submit node fires once and names itself', () {
      final flow = _flow();
      flow.choose(const ReportChoice(label: 'Auto', nodeId: 'auto'));
      expect(flow.needsAutoSubmit, isTrue);
      final submission = flow.buildAutoSubmission();
      expect(flow.needsAutoSubmit, isFalse);
      expect(submission.body['breadcrumbs'], ['root', 'auto']);
      expect(flow.history.last.destinationNodeId, 'auto');
    });

    test('completing moves to the terminal node', () {
      final flow = _flow();
      flow.completeWith(succeeded: true);
      expect(flow.isOnSuccessNode, isTrue);
      flow.completeWith(succeeded: false);
      expect(flow.isOnFailureNode, isTrue);
    });

    test('a history entry naming a node the menu dropped is skipped', () {
      final flow = _flow();
      flow.choose(flow.currentNode!.choices.first);
      final submission = flow.buildSubmission();
      expect(
        (submission.body['elements']! as Map<String, Object?>).keys,
        contains('reasons'),
      );
    });

    test('a node the menu does not contain has no current node', () {
      final flow = ReportFlow(
        menu: const ReportMenu(
          nodes: {},
          rootNodeId: 'missing',
          successNodeId: 'ok',
          failNodeId: 'bad',
        ),
        target: const GuildReportTarget('111111111111111111'),
      );
      expect(flow.currentNode, isNull);
      expect(flow.canAdvance, isFalse);
      expect(flow.advance(), isFalse);
      expect(flow.needsAutoSubmit, isFalse);
      final elements =
          flow.buildSubmission().body['elements']! as Map<String, Object?>;
      expect(elements, isEmpty);
    });
  });
}

ReportFlow _flow() => ReportFlow(
  menu: _menu(),
  target: const UserReportTarget(
    userId: '123456789012345678',
    guildId: '111111111111111111',
  ),
);

ReportMenu _menu({String? language = 'en-GB'}) => ReportMenu(
  rootNodeId: 'root',
  successNodeId: 'ok',
  failNodeId: 'bad',
  version: 7,
  variant: 'staff',
  language: language,
  nodes: {
    'root': const ReportNode(
      id: 'root',
      header: 'Why?',
      choices: [ReportChoice(label: 'Spam', nodeId: 'spam')],
      elements: [ReportElement(type: ReportElementType.freeText, name: 'note')],
    ),
    'spam': const ReportNode(
      id: 'spam',
      key: 'SPAM_SUBMIT',
      button: ReportButton(type: ReportButtonType.submit),
      elements: [
        ReportElement(
          type: ReportElementType.freeText,
          name: 'details',
          required: true,
        ),
        ReportElement(
          type: ReportElementType.checkbox,
          name: 'reasons',
          checkboxes: [
            ReportCheckboxOption(key: 'unsolicited', label: 'Unsolicited'),
            ReportCheckboxOption(
              key: 'scam',
              label: 'Scam',
              defaultSelected: true,
            ),
          ],
        ),
      ],
    ),
    'other': const ReportNode(
      id: 'other',
      button: ReportButton(type: ReportButtonType.next, target: 'spam'),
    ),
    'skipper': const ReportNode(
      id: 'skipper',
      button: ReportButton(type: ReportButtonType.next, target: 'spam'),
      elements: [ReportElement(type: ReportElementType.skip)],
    ),
    'dead-skip': const ReportNode(
      id: 'dead-skip',
      elements: [ReportElement(type: ReportElementType.skip)],
    ),
    'loop-a': const ReportNode(
      id: 'loop-a',
      button: ReportButton(type: ReportButtonType.next, target: 'loop-b'),
      elements: [ReportElement(type: ReportElementType.skip)],
    ),
    'loop-b': const ReportNode(
      id: 'loop-b',
      button: ReportButton(type: ReportButtonType.next, target: 'loop-a'),
      elements: [ReportElement(type: ReportElementType.skip)],
    ),
    'pick': const ReportNode(
      id: 'pick',
      elements: [
        ReportElement(
          type: ReportElementType.checkbox,
          name: 'bag',
          required: true,
          checkboxes: [ReportCheckboxOption(key: 'a', label: 'A')],
        ),
      ],
    ),
    'media': const ReportNode(
      id: 'media',
      elements: [
        ReportElement(
          type: ReportElementType.contentUrlInput,
          name: 'url',
          required: true,
        ),
      ],
    ),
    'nameless': const ReportNode(
      id: 'nameless',
      elements: [
        ReportElement(type: ReportElementType.contentUrlInput, required: true),
        ReportElement(type: ReportElementType.externalLink, required: true),
      ],
    ),
    'auto': const ReportNode(id: 'auto', isAutoSubmit: true),
    'ok': const ReportNode(id: 'ok'),
    'bad': const ReportNode(id: 'bad'),
  },
);
