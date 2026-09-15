/// The unicode emoji catalogue: the whole set a keyboard offers, in the
/// order CLDR puts it in, grouped the way a picker tabs it.
///
/// The names are the ones Discord resolves `:name:` against (the JoyPixels
/// naming family), because two surfaces read them: the picker's tooltip and
/// the composer's colon autocomplete. The favourites blob stores a starred
/// unicode emoji by the same name, so keeping the two in agreement is what
/// lets a favourite made in Discord's own client appear here.
///
/// Skin tones are a selector, not separate rows: a tone-capable emoji draws
/// its base glyph until a tone is chosen, then the variant for that tone.
/// The cross-tone couple combinations are not reachable from the picker, the
/// same way they are not on a keyboard palette.
library;

part 'unicode_emoji_data.dart';

enum UnicodeEmojiGroup {
  smileys,
  people,
  nature,
  food,
  travel,
  activity,
  objects,
  symbols,
  flags,
}

extension UnicodeEmojiGroupName on UnicodeEmojiGroup {
  String get label => switch (this) {
    UnicodeEmojiGroup.smileys => 'Smileys & Emotion',
    UnicodeEmojiGroup.people => 'People & Body',
    UnicodeEmojiGroup.nature => 'Animals & Nature',
    UnicodeEmojiGroup.food => 'Food & Drink',
    UnicodeEmojiGroup.travel => 'Travel & Places',
    UnicodeEmojiGroup.activity => 'Activities',
    UnicodeEmojiGroup.objects => 'Objects',
    UnicodeEmojiGroup.symbols => 'Symbols',
    UnicodeEmojiGroup.flags => 'Flags',
  };
}

/// One emoji the picker can draw, autocomplete can name, or a message can
/// carry.
final class UnicodeEmoji {
  const UnicodeEmoji({
    required this.name,
    required this.glyph,
    required this.group,
    required this.searchTerms,
    this.toneGlyphs = const [],
    this.toneNames = const [],
  });

  final String name;
  final String glyph;
  final UnicodeEmojiGroup group;
  final String searchTerms;
  final List<String> toneGlyphs;
  final List<String> toneNames;

  bool get hasSkinTones => toneGlyphs.isNotEmpty;

  /// The glyph for [tone], or the base glyph when the emoji has none for it.
  ///
  /// [tone] is 1 to 5, or 0 for the tone-less base.
  String glyphForTone(int tone) =>
      tone > 0 && tone <= toneGlyphs.length ? toneGlyphs[tone - 1] : glyph;

  /// The name for [tone], or the base name when the emoji has none for it.
  String nameForTone(int tone) =>
      tone > 0 && tone <= toneNames.length ? toneNames[tone - 1] : name;

  bool matches(String query) {
    if (query.isEmpty) return true;
    return name.contains(query) || searchTerms.contains(query);
  }
}

/// The whole catalogue, built once.
abstract final class UnicodeEmojiCatalog {
  static final List<UnicodeEmoji> all = [
    ..._expand(UnicodeEmojiGroup.smileys, _kSmileys),
    ..._expand(UnicodeEmojiGroup.people, _kPeople),
    ..._expand(UnicodeEmojiGroup.nature, _kNature),
    ..._expand(UnicodeEmojiGroup.food, _kFood),
    ..._expand(UnicodeEmojiGroup.travel, _kTravel),
    ..._expand(UnicodeEmojiGroup.activity, _kActivity),
    ..._expand(UnicodeEmojiGroup.objects, _kObjects),
    ..._expand(UnicodeEmojiGroup.symbols, _kSymbols),
    ..._expand(UnicodeEmojiGroup.flags, _kFlags),
  ];

  static final Map<UnicodeEmojiGroup, List<UnicodeEmoji>> byGroup = {
    for (final group in UnicodeEmojiGroup.values)
      group: all.where((emoji) => emoji.group == group).toList(growable: false),
  };

  static final Map<String, UnicodeEmoji> byName = {
    for (final emoji in all) emoji.name: emoji,
  };

  /// Every emoji whose name or keywords contain [query], in catalogue order.
  ///
  /// A name match outranks a keyword match, and the names themselves keep
  /// their catalogue order: typing `rocket` should not bury the rocket under
  /// four emoji that merely mention it.
  static List<UnicodeEmoji> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return all;
    return [
      ...all.where((emoji) => emoji.name.contains(needle)),
      ...all.where(
        (emoji) =>
            !emoji.name.contains(needle) && emoji.searchTerms.contains(needle),
      ),
    ];
  }

  static List<UnicodeEmoji> _expand(
    UnicodeEmojiGroup group,
    List<(String, String, String)> rows,
  ) => [
    for (final (glyph, name, search) in rows)
      () {
        final tones = _kTones[name];
        return UnicodeEmoji(
          name: name,
          glyph: glyph,
          group: group,
          searchTerms: search,
          toneGlyphs: tones == null ? const [] : tones.sublist(0, 5),
          toneNames: tones == null ? const [] : tones.sublist(5),
        );
      }(),
  ];
}
