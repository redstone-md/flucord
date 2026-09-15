import 'package:flucord/src/application/message_search_grammar.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The controls write the bar's tokens, so a mis-composed line is a filter
/// that quietly answers a different question.
void main() {
  group('MessageSearchTokenEditor.withToken', () {
    test('appends a token onto free text', () {
      expect(
        MessageSearchTokenEditor.withToken(
          'release notes',
          filter: 'from',
          value: 'Ada',
        ),
        'release notes from:Ada',
      );
    });

    test('composes a whole line from nothing', () {
      expect(
        MessageSearchTokenEditor.withToken('', filter: 'pinned', value: 'true'),
        'pinned:true',
      );
    });

    test('replaces the earlier token of the same filter', () {
      expect(
        MessageSearchTokenEditor.withToken(
          'notes before:2024-05 from:Ada after:2024',
          filter: 'from',
          value: 'Grace Hopper',
        ),
        'notes before:2024-05 after:2024 from:"Grace Hopper"',
      );
      expect(
        MessageSearchTokenEditor.withToken(
          'after:2024',
          filter: 'after',
          value: '2024-06-01',
        ),
        'after:2024-06-01',
      );
    });

    test('keeps every other filter and its quoting intact', () {
      expect(
        MessageSearchTokenEditor.withToken(
          'from:"Grace Hopper" has:image',
          filter: 'pinned',
          value: 'true',
        ),
        'from:"Grace Hopper" has:image pinned:true',
      );
    });

    test(
      'quotes an answer with whitespace and escapes the quote character',
      () {
        expect(
          MessageSearchTokenEditor.withToken(
            '',
            filter: 'from',
            value: 'Ada "Ace" Lovelace',
          ),
          r'from:"Ada \"Ace\" Lovelace"',
        );
        expect(
          MessageSearchTokenEditor.withToken(
            '',
            filter: 'from',
            value: r'back\slash',
          ),
          r'from:"back\\slash"',
        );
      },
    );
  });

  group('MessageSearchTokenEditor.withoutFilter', () {
    test('removes only the named filter', () {
      expect(
        MessageSearchTokenEditor.withoutFilter(
          'notes from:Ada has:image',
          'from',
        ),
        'notes has:image',
      );
      expect(
        MessageSearchTokenEditor.withoutFilter('pinned:true', 'pinned'),
        '',
      );
    });
  });

  group('MessageSearchTokenEditor.hasFilter and answers', () {
    test('report what the line carries', () {
      const text = 'notes from:Ada before:2024-05-01';
      expect(MessageSearchTokenEditor.hasFilter(text, 'from'), isTrue);
      expect(MessageSearchTokenEditor.hasFilter(text, 'pinned'), isFalse);
      expect(
        MessageSearchTokenEditor.answers(text, filter: 'from', value: 'Ada'),
        isTrue,
      );
      expect(
        MessageSearchTokenEditor.answers(text, filter: 'from', value: 'Grace'),
        isFalse,
      );
    });

    test('see through the quotes the editor itself wrote', () {
      final composed = MessageSearchTokenEditor.withToken(
        'notes',
        filter: 'from',
        value: 'Grace Hopper',
      );
      expect(
        MessageSearchTokenEditor.answers(
          composed,
          filter: 'from',
          value: 'Grace Hopper',
        ),
        isTrue,
      );
    });
  });

  group('grammar reads back what the editor writes', () {
    test('a composed line parses to the filter it names', () {
      const grammar = MessageSearchGrammar(
        channels: [],
        members: [
          Member(
            id: '123456789012345678',
            displayName: 'Ada "Ace" Lovelace',
            initials: 'A',
            role: 'Engineer',
            presence: Presence.online,
            colorValue: 0xff456b5a,
          ),
        ],
        currentMemberId: '123456789012345678',
      );

      final composed = MessageSearchTokenEditor.withToken(
        'release',
        filter: 'from',
        value: 'Ada "Ace" Lovelace',
      );
      final parse = grammar.parse(composed);

      expect(parse.unresolved, isEmpty);
      expect(parse.filters.content, 'release');
      expect(parse.filters.authorIds, const ['123456789012345678']);
    });
  });
}
