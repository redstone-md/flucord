import 'package:flucord/src/domain/unicode_emoji.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the catalogue covers the nine keyboard groups in CLDR order', () {
    expect(UnicodeEmojiCatalog.all.length, greaterThan(1800));
    expect(UnicodeEmojiCatalog.byGroup.keys, UnicodeEmojiGroup.values);
    // The order the groups appear in is the order a keyboard tabs them in.
    var lastSeen = -1;
    for (final emoji in UnicodeEmojiCatalog.all) {
      expect(emoji.group.index, greaterThanOrEqualTo(lastSeen));
      lastSeen = emoji.group.index;
    }
    for (final group in UnicodeEmojiGroup.values) {
      expect(UnicodeEmojiCatalog.byGroup[group]!, isNotEmpty);
    }
  });

  test('every emoji is named once, and the names Discord uses resolve', () {
    final names = <String>{};
    for (final emoji in UnicodeEmojiCatalog.all) {
      expect(names.add(emoji.name), isTrue, reason: emoji.name);
    }
    // The names the favourites blob and the colon autocomplete share.
    for (final name in ['rocket', 'thumbsup', 'joy', 'grinning', 'heart']) {
      expect(UnicodeEmojiCatalog.byName[name], isNotNull);
    }
    expect(UnicodeEmojiCatalog.byName['rocket']!.glyph, '🚀');
    expect(UnicodeEmojiCatalog.byName['thumbsup']!.glyph, '👍');
  });

  test('a tone-capable emoji swaps its glyph and its name per tone', () {
    final wave = UnicodeEmojiCatalog.byName['wave']!;
    expect(wave.hasSkinTones, isTrue);
    expect(wave.glyphForTone(0), '👋');
    expect(wave.glyphForTone(1), '👋🏻');
    expect(wave.glyphForTone(5), '👋🏿');
    expect(wave.nameForTone(5), 'wave_tone5');
    // The tone names are what the favourites blob would store.
    expect(
      UnicodeEmojiCatalog.byName.containsKey('wave_tone5'),
      isFalse,
      reason: 'variants hang off their base, not the flat name table',
    );

    // An emoji without tones answers with its base whatever is asked.
    final rocket = UnicodeEmojiCatalog.byName['rocket']!;
    expect(rocket.hasSkinTones, isFalse);
    expect(rocket.glyphForTone(3), '🚀');
    expect(rocket.nameForTone(3), 'rocket');
  });

  test('search ranks a name match above a keyword match', () {
    final byName = UnicodeEmojiCatalog.search('rocket');
    expect(byName.first.name, 'rocket');
    // `launch` names no emoji; it is a word of the rocket's.
    final byKeyword = UnicodeEmojiCatalog.search('launch');
    expect(byKeyword, isNotEmpty);
    expect(byKeyword.any((emoji) => emoji.name == 'rocket'), isTrue);
    expect(UnicodeEmojiCatalog.search('nothing is named this'), isEmpty);
  });
}
