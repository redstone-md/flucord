import 'dart:ui' as ui;

import 'package:flucord/src/data/discord/display_name_fonts.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/display_name.dart';
import 'package:flucord/src/presentation/widgets/name_effect.dart';
import 'package:flucord/src/presentation/widgets/name_style_scope.dart';
import 'package:flucord/src/presentation/widgets/nameplate_motion.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/contrast.dart';

const _red = 0xffff0000;
const _green = 0xff00ff00;
const _blue = 0xff0000ff;

final class _NoVideos implements NameplateVideos {
  @override
  NameplateVideo open(String url) => throw UnimplementedError();
}

Future<void> _pumpName(
  WidgetTester tester,
  NameStyle? style, {
  DisplayNameFonts? fonts,
  bool inServer = false,
  int? roleColor,
}) {
  final name = DisplayName(
    'Freez',
    style: FlucordTextRole.label.style.copyWith(color: Colors.white),
    nameStyle: style,
    inServer: inServer,
    roleColor: roleColor,
  );
  return tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('name'),
            // Room for what an effect draws outside the letters.
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: switch (fonts) {
                final fonts? => NameStyleScope(
                  videos: _NoVideos(),
                  fonts: fonts,
                  child: name,
                ),
                null => name,
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// The colour at [point], in the coordinates of the whole screen.
Future<Color> _pixel(WidgetTester tester, Offset point) async {
  final finder = find.byKey(const ValueKey('name'));
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final local = point - tester.getTopLeft(finder);
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    return image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  final offset =
      (local.dy.floor() * boundary.size.width.toInt() + local.dx.floor()) * 4;
  return Color.fromARGB(
    bytes!.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

/// Where the test font draws the letters: each is a full square of one em,
/// in the middle of the line.
Rect _letters(WidgetTester tester) {
  final line = tester.getRect(find.text('Freez').last);
  final size = FlucordTextRole.label.size;
  return Rect.fromLTRB(
    line.left,
    line.center.dy - size / 2,
    line.right,
    line.center.dy + size / 2,
  );
}

TextStyle _drawnStyle(WidgetTester tester) =>
    tester.widget<Text>(find.text('Freez').last).style!;

/// A fonts loader that records what it is asked to fetch.
(DisplayNameFonts, List<Uri>) _recordingFonts({
  Future<void> Function(String family, Uint8List bytes)? register,
}) {
  final fetched = <Uri>[];
  final fonts = DisplayNameFonts(
    fetch: (url) async {
      fetched.add(url);
      final font = await rootBundle.load(
        'assets/fonts/golos_text/GolosText-Regular.ttf',
      );
      return font.buffer.asUint8List();
    },
    register: register ?? (family, bytes) async {},
  );
  return (fonts, fetched);
}

void main() {
  group('a name font', () {
    testWidgets('a known id is fetched and drawn in its font', (tester) async {
      final (fonts, fetched) = _recordingFonts();

      await _pumpName(
        tester,
        const NameStyle(colors: [], fontId: 14),
        fonts: fonts,
      );

      expect(fetched, [DisplayNameFont.mainframe.url]);
      await tester.runAsync(() => fonts.loaded(DisplayNameFont.mainframe));
      await tester.pump();
      final style = _drawnStyle(tester);
      expect(style.fontFamily, 'Orbitron');
      expect(style.fontFamilyFallback, [FlucordType.family]);
    });

    testWidgets('an unknown id fetches nothing and keeps the app font', (
      tester,
    ) async {
      final (fonts, fetched) = _recordingFonts();

      await _pumpName(
        tester,
        const NameStyle(colors: [], fontId: 7),
        fonts: fonts,
      );

      expect(fetched, isEmpty);
      expect(_drawnStyle(tester).fontFamily, FlucordType.family);
    });

    testWidgets('the line keeps its height when the font arrives', (
      tester,
    ) async {
      final (fonts, _) = _recordingFonts(
        register: (family, bytes) =>
            (FontLoader(family)..addFont(
                  Future.value(ByteData.sublistView(bytes)),
                ))
                .load(),
      );
      await _pumpName(tester, null);
      final plain = tester.getSize(find.text('Freez'));

      await _pumpName(
        tester,
        const NameStyle(colors: [], fontId: 3),
        fonts: fonts,
      );
      final waiting = tester.getSize(find.text('Freez'));
      await tester.runAsync(() => fonts.loaded(DisplayNameFont.sakura));
      await tester.pump();
      final arrived = tester.getSize(find.text('Freez'));

      expect(arrived.width, isNot(waiting.width), reason: 'the font changed');
      expect(waiting.height, plain.height);
      expect(arrived.height, plain.height);
    });

    testWidgets('the name keeps its width until its font arrives', (
      tester,
    ) async {
      final (fonts, _) = _recordingFonts();
      await _pumpName(tester, null);
      final plain = tester.getSize(find.text('Freez'));

      await _pumpName(
        tester,
        const NameStyle(colors: [], fontId: 3),
        fonts: fonts,
      );

      expect(tester.getSize(find.text('Freez')).width, plain.width);
    });

    testWidgets('a name in a server keeps its font beside the role colour', (
      tester,
    ) async {
      final (fonts, _) = _recordingFonts();

      await _pumpName(
        tester,
        const NameStyle(colors: [_red], fontId: 14, effectId: 3),
        fonts: fonts,
        inServer: true,
        roleColor: _blue,
      );
      await tester.runAsync(() => fonts.loaded(DisplayNameFont.mainframe));
      await tester.pump();

      expect(_drawnStyle(tester).fontFamily, 'Orbitron');
      expect(_drawnStyle(tester).color, const Color(_blue));
      expect(find.text('Freez'), findsOneWidget, reason: 'no effect layers');
    });
  });

  group('a name effect', () {
    testWidgets('neon is white letters glowing in the colour', (tester) async {
      await _pumpName(tester, const NameStyle(colors: [_red], effectId: 3));
      final letters = _letters(tester);

      final inside = await _pixel(tester, letters.center);
      final above = await _pixel(
        tester,
        Offset(letters.center.dx, letters.top - 3),
      );

      expect(inside, Colors.white);
      expect(above.r, greaterThan(above.g + 0.1), reason: 'a red glow');
    });

    testWidgets('toon shades from light at the top to the colour', (
      tester,
    ) async {
      await _pumpName(tester, const NameStyle(colors: [_red], effectId: 4));
      final letters = _letters(tester);

      final top = await _pixel(
        tester,
        Offset(letters.center.dx, letters.top + 2),
      );
      final bottom = await _pixel(
        tester,
        Offset(letters.center.dx, letters.bottom - 2),
      );

      expect(top.computeLuminance(), greaterThan(bottom.computeLuminance()));
      expect(bottom.r, greaterThan(bottom.g + 0.2));
    });

    testWidgets('pop is white letters over a copy in the colour', (
      tester,
    ) async {
      await _pumpName(tester, const NameStyle(colors: [_red], effectId: 5));
      final letters = _letters(tester);

      final inside = await _pixel(tester, letters.center);
      final belowEdge = await _pixel(
        tester,
        Offset(letters.center.dx, letters.bottom + 2),
      );

      expect(inside, Colors.white);
      expect(belowEdge.r, greaterThan(belowEdge.g + 0.2), reason: 'red copy');
    });

    testWidgets('prism runs through the colours and back to the first', (
      tester,
    ) async {
      await _pumpName(
        tester,
        const NameStyle(colors: [_red, _green, _blue], effectId: 7),
      );
      final letters = _letters(tester);
      Future<Color> at(double fraction) => _pixel(
        tester,
        Offset(letters.left + letters.width * fraction, letters.center.dy),
      );

      final start = await at(0.02);
      final second = await at(1 / 3);
      final third = await at(2 / 3);
      final end = await at(0.98);

      expect(start.r, greaterThan(start.g));
      expect(second.g, greaterThan(second.r));
      expect(third.b, greaterThan(third.g));
      expect(end.r, greaterThan(end.b));
    });

    testWidgets('an effect this client does not draw is the plain name', (
      tester,
    ) async {
      for (final effect in [6, 8, 1001, null]) {
        await _pumpName(tester, NameStyle(colors: [_red], effectId: effect));

        expect(find.text('Freez'), findsOneWidget, reason: 'effect $effect');
        expect(_drawnStyle(tester).color, Colors.white);
      }
    });
  });

  group('a drawn effect reads on every surface', () {
    // Black, white, grey, and Discord's own swatches.
    const colors = [
      0xff000000,
      0xffffffff,
      0xff808080,
      _red,
      _blue,
      0xffffff00,
      0xff18b491,
      0xff3598db,
      0xff995ab8,
      0xffe91d63,
      0xfff1c410,
      0xffe74c3c,
    ];

    for (final theme in [FlucordTheme.dark, FlucordTheme.light]) {
      final surfaces = theme.extension<FlucordSurfaceTheme>()!;
      for (final effect in NameEffect.values) {
        test('${effect.name} in the ${theme.brightness.name} theme', () {
          for (final color in colors) {
            final look = effect.look([color, ...colors.take(2)], surfaces);
            for (final background in surfaces.backgrounds) {
              final outline = look.outline;
              final readable =
                  look.fill.every((fill) => contrast(fill, background) >= 4.5) ||
                  (outline != null && contrast(outline, background) >= 4.5);
              expect(
                readable,
                isTrue,
                reason: '${Color(color)} on $background',
              );
            }
          }
        });
      }
    }

    test('a colour that already reads is kept', () {
      final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
      const light = 0xfff1c410;

      expect(NameEffect.solid.look([light], surfaces).fill, [
        const Color(light),
      ]);
    });
  });
}
