import 'package:flucord/src/application/accessibility_controller.dart';
import 'package:flucord/src/data/spell_check/word_list_spell_check_service.dart';
import 'package:flucord/src/domain/accessibility.dart';
import 'package:flucord/src/presentation/widgets/accessibility_scope.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/presentation/widgets/spell_check_scope.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the word list service', () {
    test('knows the words it was bundled with', () async {
      final service = WordListSpellCheckService();
      await service.fetchSpellCheckSuggestions(
        const Locale('en'),
        'load the asset',
      );

      expect(service.knows('hello'), isTrue);
      expect(service.knows('Hello'), isTrue, reason: 'casing is not a typo');
      expect(service.knows('helloo'), isFalse);
    });

    test('underlines only the words the dictionary does not know', () async {
      final service = WordListSpellCheckService();

      final spans = await service.fetchSpellCheckSuggestions(
        const Locale('en'),
        'welll hello there',
      );

      expect(spans, isNotNull);
      expect(spans, hasLength(1));
      final span = spans!.single;
      expect(span.range.start, 0);
      expect(span.range.end, 5);
      // The underline is the answer: suggestions are left to the machine
      // that can compute them.
      expect(span.suggestions, isEmpty);
    });

    test('empty text underlines nothing', () async {
      final service = WordListSpellCheckService();

      expect(
        await service.fetchSpellCheckSuggestions(const Locale('en'), ''),
        isEmpty,
      );
    });
  });

  group('the composer', () {
    final sent = <String>[];

    Future<void> pump(
      WidgetTester tester, {
      required AccessibilityController accessibility,
      required SpellCheckService service,
    }) async {
      sent.clear();
      await tester.binding.setSurfaceSize(const Size(900, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: AccessibilityScope(
              controller: accessibility,
              child: SpellCheckScope(
                service: service,
                child: MessageComposer(
                  channelId: 'general',
                  channelName: 'general',
                  spaceName: 'The Forge',
                  emojiSections: const [],
                  stickerSections: const [],
                  isSending: false,
                  characterLimit: 2000,
                  onSend: (body, _, _, _) async {
                    sent.add(body);
                    return true;
                  },
                  onCreatePoll: (_) async => true,
                  onSendStickers: (_) async => true,
                  onCancelReply: () {},
                  onTyping: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    AccessibilityController makeController({bool spellcheck = true}) {
      final repository = _MemorySettings()
        ..stored = AccessibilitySettings(spellcheck: spellcheck);
      return AccessibilityController(repository);
    }

    testWidgets('a misspelling is underlined while it is typed', (
      tester,
    ) async {
      final controller = makeController();
      addTearDown(controller.dispose);
      await controller.load();
      await pump(
        tester,
        accessibility: controller,
        service: _FakeDictionary({'hello', 'there'}),
      );

      await tester.enterText(
        find.byKey(const ValueKey('message-composer')),
        'welll hello',
      );
      await tester.pump();

      // The field drew an underline: its span reached the state that builds
      // the text the reader sees.
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('message-composer')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.spellCheckConfiguration?.spellCheckEnabled, isTrue);
      final spellCheckResults = tester
          .state<EditableTextState>(
            find.descendant(
              of: find.byKey(const ValueKey('message-composer')),
              matching: find.byType(EditableText),
            ),
          )
          .spellCheckResults;
      expect(spellCheckResults?.suggestionSpans, hasLength(1));
      expect(
        spellCheckResults?.suggestionSpans.single.range.start,
        0,
        reason: 'the misspelling is the first word',
      );
    });

    testWidgets('the switch off leaves the text unmarked', (tester) async {
      final controller = makeController(spellcheck: false);
      addTearDown(controller.dispose);
      await controller.load();
      await pump(
        tester,
        accessibility: controller,
        service: _FakeDictionary({'hello', 'there'}),
      );

      await tester.enterText(
        find.byKey(const ValueKey('message-composer')),
        'welll hello',
      );
      await tester.pump();

      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('message-composer')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.spellCheckConfiguration?.spellCheckEnabled, isFalse);
    });

    testWidgets('the send carries exactly what was typed', (tester) async {
      final controller = makeController();
      addTearDown(controller.dispose);
      await controller.load();
      await pump(
        tester,
        accessibility: controller,
        service: _FakeDictionary({'hello', 'there'}),
      );

      await tester.enterText(
        find.byKey(const ValueKey('message-composer')),
        'welll hello',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send-message')));
      await tester.pumpAndSettle();

      // The underline marked a word and the message still went out with it:
      // a misspelling is information for whoever is typing, not something
      // the client edits for them.
      expect(sent, ['welll hello']);
    });
  });
}

/// A dictionary the test controls, so the composer is exercised without the
/// bundled word list and its asynchronous read.
final class _FakeDictionary implements SpellCheckService {
  _FakeDictionary(this.known);

  final Set<String> known;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    final spans = <SuggestionSpan>[];
    for (final match in RegExp(r'[A-Za-z]+').allMatches(text)) {
      if (known.contains(match[0]!.toLowerCase())) continue;
      spans.add(
        SuggestionSpan(TextRange(start: match.start, end: match.end), const []),
      );
    }
    return spans;
  }
}

final class _MemorySettings implements AccessibilityRepository {
  AccessibilitySettings stored = const AccessibilitySettings();

  @override
  Future<AccessibilitySettings> load() async => stored;

  @override
  Future<void> save(AccessibilitySettings settings) async {
    stored = settings;
  }
}
