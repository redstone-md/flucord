import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_report_mapper.dart';
import 'package:flucord/src/domain/moderation_report.dart';

void main() {
  test('reads a whole menu', () {
    final menu = DiscordReportMapper.menu(_menuPayload)!;
    expect(menu.rootNodeId, 'root');
    expect(menu.successNodeId, 'ok');
    expect(menu.failNodeId, 'bad');
    expect(menu.version, 7);
    expect(menu.variant, 'staff');
    expect(menu.language, 'en-GB');
    expect(menu.nodes.keys, containsAll(['root', 'spam', 'ok', 'bad']));

    final root = menu['root']!;
    expect(root.header, 'What is wrong?');
    expect(root.subheader, 'Pick the closest thing');
    expect(root.info, 'Reports are confidential');
    expect(root.choices.map((choice) => choice.label), ['Spam', 'Other']);
    expect(root.choices.first.nodeId, 'spam');
    expect(root.button, isNull);

    final spam = menu['spam']!;
    expect(spam.key, 'SPAM_SUBMIT');
    expect(spam.reportSubtype, 'sub_spam');
    expect(spam.isAutoSubmit, isFalse);
    expect(spam.button!.type, ReportButtonType.submit);
    expect(spam.multiSelect, isNotNull);
    expect(spam.textInputs.map((element) => element.name), ['details']);

    final details = spam.elements.firstWhere(
      (element) => element.name == 'details',
    );
    expect(details.type, ReportElementType.freeText);
    expect(details.required, isTrue);
    expect(details.title, 'Tell us more');
    expect(details.placeholder, 'What happened?');
    expect(details.characterLimit, 400);
    expect(details.rows, 3);
    expect(details.isSingleLine, isFalse);
    expect(details.pattern, r'^\S+');

    final reasons = spam.multiSelect!;
    expect(reasons.checkboxes.map((option) => option.key), [
      'unsolicited',
      'scam',
    ]);
    expect(reasons.checkboxes.first.label, 'Unsolicited DMs');
    expect(reasons.checkboxes.first.subtitle, 'Sent without asking');
    expect(reasons.checkboxes.last.defaultSelected, isTrue);
  });

  test('a menu with no node graph is refused', () {
    expect(DiscordReportMapper.menu(const {}), isNull);
    expect(
      DiscordReportMapper.menu(const {
        'root_node_id': 'root',
        'success_node_id': 'ok',
        'fail_node_id': 'bad',
        'nodes': 'not a map',
      }),
      isNull,
    );
  });

  test('a menu whose root is not in the graph is refused', () {
    expect(
      DiscordReportMapper.menu(const {
        'root_node_id': 'root',
        'success_node_id': 'ok',
        'fail_node_id': 'bad',
        'nodes': <String, Object?>{
          'ok': {'id': 'ok'},
        },
      }),
      isNull,
    );
  });

  test('an element type this build has never seen becomes unknown', () {
    final element = DiscordReportMapper.element(const {
      'type': 'holographic_preview',
      'name': 'x',
    });
    expect(element.type, ReportElementType.unknown);
    expect(element.required, isFalse);
    expect(ReportElementType.fromWire(null), ReportElementType.unknown);
    expect(ReportButtonType.fromWire('nope'), ReportButtonType.unknown);
  });

  test('malformed children, options and checkbox rows are skipped', () {
    final node = DiscordReportMapper.node('n', const {
      'children': [
        ['Label', 'target'],
        ['only one'],
        'not a list',
        [null, null],
      ],
      'elements': [
        {
          'type': 'dropdown',
          'name': 'pick',
          'data': {
            'options': [
              {'value': 'a', 'label': 'A'},
              {'label': 'no value'},
              'not a map',
            ],
          },
        },
        {
          'type': 'checkbox',
          'name': 'bag',
          'data': [
            ['k'],
            [],
            'not a list',
            [null],
          ],
        },
        'not a map',
      ],
    });
    expect(node.choices, hasLength(1));
    expect(node.choices.single.label, 'Label');
    final dropdown = node.elements.first;
    expect(dropdown.options, hasLength(1));
    expect(dropdown.options.single.label, 'A');
    final checkbox = node.elements[1];
    expect(checkbox.checkboxes, hasLength(1));
    // A row with only a key falls back to the key as its label.
    expect(checkbox.checkboxes.single.label, 'k');
    expect(checkbox.checkboxes.single.subtitle, isNull);
  });

  test('a choice with no label falls back to its node id', () {
    final node = DiscordReportMapper.node('n', const {
      'children': [
        [null, 'target'],
      ],
    });
    expect(node.choices.single.label, 'target');
  });

  test('a text element reads its body from either key', () {
    final withBody = DiscordReportMapper.element(const {
      'type': 'text',
      'data': {'body': 'Body copy'},
    });
    expect(withBody.body, 'Body copy');
    final withHeader = DiscordReportMapper.element(const {
      'type': 'text',
      'data': {'header': 'Header copy'},
    });
    expect(withHeader.body, 'Header copy');
    final withNeither = DiscordReportMapper.element(const {'type': 'text'});
    expect(withNeither.body, isNull);
  });

  test('the node graph is bounded', () {
    final nodes = <String, Object?>{
      'root': const {'id': 'root'},
      for (var index = 0; index < DiscordReportMapper.maxNodes + 40; index++)
        'n$index': {'id': 'n$index'},
    };
    final menu = DiscordReportMapper.menu({
      'root_node_id': 'root',
      'success_node_id': 'root',
      'fail_node_id': 'root',
      'nodes': nodes,
    });
    expect(menu!.nodes.length, DiscordReportMapper.maxNodes);
  });

  test('a node\'s own lists are bounded too', () {
    final oversized = [
      for (
        var index = 0;
        index < DiscordReportMapper.maxNodeItems + 20;
        index++
      )
        ['label$index', 'node$index'],
    ];
    final node = DiscordReportMapper.node('n', {
      'children': oversized,
      'elements': [
        {
          'type': 'dropdown',
          'name': 'pick',
          'data': {
            'options': [
              for (
                var index = 0;
                index < DiscordReportMapper.maxNodeItems + 20;
                index++
              )
                {'value': '$index'},
            ],
          },
        },
        for (
          var index = 0;
          index < DiscordReportMapper.maxNodeItems + 20;
          index++
        )
          {'type': 'text'},
      ],
    });
    expect(node.choices, hasLength(DiscordReportMapper.maxNodeItems));
    expect(node.elements, hasLength(DiscordReportMapper.maxNodeItems));
    expect(
      node.elements.first.options,
      hasLength(DiscordReportMapper.maxNodeItems),
    );
  });

  test('a checkbox list is bounded', () {
    final element = DiscordReportMapper.element({
      'type': 'checkbox',
      'name': 'bag',
      'data': [
        for (
          var index = 0;
          index < DiscordReportMapper.maxNodeItems + 20;
          index++
        )
          ['k$index', 'L$index'],
      ],
    });
    expect(element.checkboxes, hasLength(DiscordReportMapper.maxNodeItems));
  });
}

const _menuPayload = <String, Object?>{
  'root_node_id': 'root',
  'success_node_id': 'ok',
  'fail_node_id': 'bad',
  'version': 7,
  'variant': 'staff',
  'language': 'en-GB',
  'nodes': <String, Object?>{
    'root': {
      'id': 'root',
      'header': 'What is wrong?',
      'subheader': 'Pick the closest thing',
      'info': 'Reports are confidential',
      'children': [
        ['Spam', 'spam'],
        ['Other', 'other'],
      ],
    },
    'spam': {
      'id': 'spam',
      'key': 'SPAM_SUBMIT',
      'header': 'Spam',
      'report_type': 'sub_spam',
      'button': {'type': 'submit'},
      'elements': [
        {
          'type': 'free_text',
          'name': 'details',
          'should_submit_data': true,
          'data': {
            'title': 'Tell us more',
            'placeholder': 'What happened?',
            'character_limit': 400,
            'rows': 3,
            'pattern': r'^\S+',
          },
        },
        {
          'type': 'checkbox',
          'name': 'reasons',
          'data': [
            ['unsolicited', 'Unsolicited DMs', 'Sent without asking', false],
            ['scam', 'Scam links', null, true],
          ],
        },
      ],
    },
    'ok': {'id': 'ok'},
    'bad': {'id': 'bad'},
  },
};
