import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The icons drawn in Figma frame "B · Linear, вставной холст".
  const frameB = <String, IconData>{
    'text channel': FlucordIcons.textChannel,
    'voice channel': FlucordIcons.voiceChannel,
    'chevron down': FlucordIcons.chevronDown,
    'chevron right': FlucordIcons.chevronRight,
    'search': FlucordIcons.search,
    'inbox': FlucordIcons.inbox,
    'pin': FlucordIcons.pin,
    'members': FlucordIcons.members,
    'threads': FlucordIcons.threads,
    'mic': FlucordIcons.mic,
    'headphones': FlucordIcons.headphones,
    'settings': FlucordIcons.settings,
    'camera': FlucordIcons.camera,
    'screen share': FlucordIcons.screenShare,
    'hang up': FlucordIcons.hangUp,
    'add': FlucordIcons.add,
    'emoji': FlucordIcons.emoji,
    'reply': FlucordIcons.reply,
    'direct messages': FlucordIcons.directMessages,
    'image': FlucordIcons.image,
    'explore': FlucordIcons.explore,
    'more': FlucordIcons.more,
    'signal': FlucordIcons.signal,
    'mention': FlucordIcons.mention,
    'mail': FlucordIcons.mail,
  };

  test('every icon in frame B is drawn by Lucide at one stroke weight', () {
    // Weight 300 is Lucide's 1.5 stroke, the closest to the design's 1.75.
    for (final MapEntry(key: meaning, value: icon) in frameB.entries) {
      expect(icon.fontPackage, 'lucide_icons_flutter', reason: meaning);
      expect(icon.fontFamily, 'Lucide300', reason: meaning);
    }
  });

  test('no two meanings share a glyph', () {
    final glyphs = frameB.values.map((icon) => icon.codePoint).toSet();

    expect(glyphs, hasLength(frameB.length));
  });

  test('icons that point a way mirror in right-to-left text, as before', () {
    // Material mirrors these three, so the swap must not stop doing it.
    final mirrored = frameB.entries
        .where((entry) => entry.value.matchTextDirection)
        .map((entry) => entry.key);

    expect(
      mirrored,
      unorderedEquals(['chevron right', 'screen share', 'reply']),
    );
  });
}
