import 'dart:io';
import 'dart:typed_data';

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

  test('a font is fetched once and registered under its family', () async {
    final fetched = <Uri>[];
    final registered = <(String, Uint8List)>[];
    final bytes = Uint8List.fromList([1, 2, 3]);
    final fonts = DisplayNameFonts(
      fetch: (url) async {
        fetched.add(url);
        return bytes;
      },
      register: (family, bytes) async => registered.add((family, bytes)),
    );

    fonts.request(DisplayNameFont.mainframe);
    fonts.request(DisplayNameFont.mainframe);
    await fonts.loaded(DisplayNameFont.mainframe);

    expect(fetched, [DisplayNameFont.mainframe.url]);
    expect(fetched.single.host, 'fonts.gstatic.com');
    expect(registered, [('Orbitron', bytes)]);
  });

  test('a font that cannot be fetched is not registered', () async {
    final registered = <String>[];
    final fonts = DisplayNameFonts(
      fetch: (url) async => throw const HttpException('404'),
      register: (family, bytes) async => registered.add(family),
    );

    await fonts.loaded(DisplayNameFont.sakura);

    expect(registered, isEmpty);
  });
}
