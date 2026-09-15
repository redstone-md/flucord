import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../domain/spellcheck.dart';

/// A [SpellCheckService] over a word list bundled with the app.
///
/// The whole point is that spellcheck is local: the dictionary is read once
/// into memory and consulted in-process, and no text ever leaves the app.
/// The bundle is a SCOWL-derived list of lowercase words, so a capitalised
/// word is judged by its lowercase form, which is how a sentence start or
/// a name typed in lower case still underlines correctly.
final class WordListSpellCheckService
    implements SpellCheckService, SpellDictionary {
  WordListSpellCheckService({this.asset = defaultAsset});

  /// Where the word list is bundled.
  static const defaultAsset = 'assets/spellcheck/en.txt';

  final String asset;

  Set<String>? _words;

  /// Reads the word list once. Safe to call repeatedly: the words are read
  /// only on the first call, so a check before every keystroke costs a set
  /// lookup and nothing else.
  Future<void> _ensureLoaded() async {
    if (_words != null) return;
    final text = await rootBundle.loadString(asset);
    _words = LineSplitter().convert(text).toSet();
  }

  @override
  bool knows(String word) {
    final words = _words;
    // Before the list has been read, underlining nothing is the honest
    // answer: a wrong underline is worse than a missing one.
    if (words == null) return true;
    final lower = word.toLowerCase();
    return words.contains(lower) || words.contains(word);
  }

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (text.isEmpty) return const [];
    await _ensureLoaded();
    // Words and their offsets are collected in one pass so each
    // misspelling's own span reaches the underline.
    final spans = <SuggestionSpan>[];
    for (final match in RegExp(r'[A-Za-z]+').allMatches(text)) {
      final word = match[0]!;
      if (knows(word)) continue;
      // Suggestions are left empty: the underline is what the reader is
      // after here, and inventing corrections from a bare list of words
      // would be guessing.
      spans.add(
        SuggestionSpan(TextRange(start: match.start, end: match.end), const []),
      );
    }
    return spans;
  }
}
