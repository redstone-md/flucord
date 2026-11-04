import 'package:flucord/src/data/discord/display_name_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a known font id names its font, an unknown one none', () {
    expect(DisplayNameFont.byId(3)?.family, 'Cherry Bomb One');
    expect(DisplayNameFont.byId(14)?.family, 'Orbitron');
    // Discord's own font, a retired one, and ones with no file to fetch.
    for (final id in [11, 1, 7, 10, 17, 99, null]) {
      expect(DisplayNameFont.byId(id), isNull, reason: 'font $id');
    }
  });

  test('a font is loaded once and drawn under the family it got', () async {
    final loads = <DisplayNameFont>[];
    final fonts = DisplayNameFonts(
      load: (font) async {
        loads.add(font);
        return 'Orbitron_700';
      },
    );

    fonts.request(DisplayNameFont.mainframe);
    fonts.request(DisplayNameFont.mainframe);
    expect(fonts.familyOf(DisplayNameFont.mainframe), isNull);
    await fonts.loaded(DisplayNameFont.mainframe);

    expect(loads, [DisplayNameFont.mainframe]);
    expect(fonts.familyOf(DisplayNameFont.mainframe), 'Orbitron_700');
  });

  test('a font that fails stays in the app font and does not hold back '
      'the next', () async {
    final fonts = DisplayNameFonts(
      load: (font) async => font == DisplayNameFont.sakura
          ? throw StateError('offline')
          : font.family,
    );

    fonts.request(DisplayNameFont.sakura);
    await fonts.loaded(DisplayNameFont.journal);

    expect(fonts.familyOf(DisplayNameFont.sakura), isNull);
    expect(fonts.familyOf(DisplayNameFont.journal), 'Kalam');
  });
}
