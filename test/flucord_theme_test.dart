import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/theme/file_theme_store.dart';
import 'package:flucord/src/domain/flucord_palette.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/contrast.dart';

void main() {
  test('light theme keeps rail, sidebar and chat distinct', () {
    final surfaces = FlucordTheme.light.extension<FlucordSurfaceTheme>()!;

    expect(surfaces.rail, isNot(surfaces.canvas));
    expect(surfaces.surface, isNot(surfaces.canvas));
  });

  test('desktop controls resolve quiet default and blurple focus states', () {
    final theme = FlucordTheme.dark;
    final surfaces = theme.extension<FlucordSurfaceTheme>()!;
    final style = theme.iconButtonTheme.style!;

    expect(style.foregroundColor!.resolve({}), surfaces.muted);
    expect(
      style.foregroundColor!.resolve({WidgetState.hovered}),
      theme.colorScheme.onSurface,
    );
    expect(
      style.overlayColor!.resolve({WidgetState.focused}),
      surfaces.brand.withValues(alpha: 0.2),
    );
    final filled = theme.filledButtonTheme.style!;
    expect(filled.backgroundColor!.resolve({}), surfaces.brand);
    expect(
      filled.backgroundColor!.resolve({WidgetState.pressed}),
      surfaces.brandPressed,
    );
  });

  test('surface roles interpolate without dropping semantic fields', () {
    final dark = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
    final light = FlucordTheme.light.extension<FlucordSurfaceTheme>()!;
    final midpoint = dark.lerp(light, 0.5);

    expect(midpoint.rail, Color.lerp(dark.rail, light.rail, 0.5));
    expect(midpoint.control, Color.lerp(dark.control, light.control, 0.5));
    expect(midpoint.danger, Color.lerp(dark.danger, light.danger, 0.5));
    expect(midpoint.link, Color.lerp(dark.link, light.link, 0.5));
  });

  test('every palette colour reaches widgets through the surface theme', () {
    const palette = FlucordPalette(
      isDark: true,
      rail: 0xff000001,
      canvas: 0xff000002,
      surface: 0xff000003,
      raised: 0xff000004,
      inset: 0xff000005,
      control: 0xff000006,
      text: 0xff000007,
      muted: 0xff000008,
      border: 0xff000009,
      brand: 0xff00000a,
      brandPressed: 0xff00000b,
      success: 0xff00000c,
      warning: 0xff00000d,
      mention: 0xff00000e,
      danger: 0xff00000f,
      offline: 0xff000010,
    );

    final surfaces = FlucordTheme.fromPalette(
      palette,
    ).extension<FlucordSurfaceTheme>()!;

    expect(surfaces.rail, const Color(0xff000001));
    expect(surfaces.canvas, const Color(0xff000002));
    expect(surfaces.surface, const Color(0xff000003));
    expect(surfaces.raised, const Color(0xff000004));
    expect(surfaces.inset, const Color(0xff000005));
    expect(surfaces.control, const Color(0xff000006));
    expect(surfaces.text, const Color(0xff000007));
    expect(surfaces.muted, const Color(0xff000008));
    expect(surfaces.border, const Color(0xff000009));
    expect(surfaces.brand, const Color(0xff00000a));
    expect(surfaces.brandPressed, const Color(0xff00000b));
    expect(surfaces.success, const Color(0xff00000c));
    expect(surfaces.warning, const Color(0xff00000d));
    expect(surfaces.mention, const Color(0xff00000e));
    expect(surfaces.danger, const Color(0xff00000f));
    expect(surfaces.offline, const Color(0xff000010));
  });

  testWidgets('an installed theme paints buttons in its own brand', (
    tester,
  ) async {
    const brand = Color(0xff2a9d8f);
    const pressed = Color(0xff1f776c);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.fromPalette(
          FlucordPalette.dark.copyWith(
            brand: brand.toARGB32(),
            brandPressed: pressed.toARGB32(),
          ),
        ),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Save')),
              const FilledButton(onPressed: null, child: Text('Off')),
            ],
          ),
        ),
      ),
    );

    Color fill(String label) => tester
        .widget<Material>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Material))
              .first,
        )
        .color!;

    expect(fill('Save'), brand);
    expect(fill('Off'), brand.withValues(alpha: 0.38));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Save')),
    );
    await tester.pumpAndSettle();
    expect(fill('Save'), pressed);
    await gesture.up();
  });

  group('WCAG AA contrast', () {
    test('the measure agrees with published values', () {
      expect(contrast(Colors.black, Colors.white), closeTo(21, 0.01));
      // WebAIM's reference grey: the lightest that passes on white.
      expect(
        contrast(const Color(0xff767676), Colors.white),
        closeTo(4.54, 0.01),
      );
    });

    final themes = <String, FlucordPalette>{
      'dark': FlucordPalette.dark,
      'light': FlucordPalette.light,
      'the example theme': FlucordPalette.fromJson(
        (jsonDecode(exampleTheme) as Map<String, Object?>)['palette'],
      ),
    };

    themes.forEach((name, palette) {
      group('in $name', () {
        final theme = FlucordTheme.fromPalette(palette);
        final surfaces = theme.extension<FlucordSurfaceTheme>()!;

        void expectContrast(Color foreground, double minimum) =>
            expectReadable(theme, foreground, minimum);

        test(
          'link text reaches 4.5:1',
          () => expectContrast(surfaces.link, 4.5),
        );

        test(
          'error text reaches 4.5:1',
          () => expectContrast(surfaces.errorText, 4.5),
        );

        // Widgets and Material's own fields draw error text in it.
        test(
          'the scheme\'s error colour reaches 4.5:1',
          () => expectContrast(theme.colorScheme.error, 4.5),
        );

        test(
          'the default icon colour reaches 3:1',
          () => expectContrast(surfaces.muted, 3),
        );

        test(
          'the accent icon reaches 3:1',
          () => expectContrast(surfaces.accentIcon, 3),
        );

        test(
          'the focus ring reaches 3:1',
          () => expectContrast(surfaces.focusRing, 3),
        );
      });
    });

    test('a theme colour that already reads is kept as written', () {
      const brand = 0xffffc0cb;
      const danger = 0xffffb0b0;
      final surfaces = FlucordTheme.fromPalette(
        FlucordPalette.dark.copyWith(brand: brand, danger: danger),
      ).extension<FlucordSurfaceTheme>()!;

      expect(surfaces.link, const Color(brand));
      expect(surfaces.errorText, const Color(danger));
      expect(surfaces.accentIcon, const Color(brand));
      expect(surfaces.focusRing, const Color(brand));
    });

    // A theme file may give a colour alpha. What people read is that colour
    // mixed with the background, so that mix is what has to reach the ratio.
    test('a see-through theme colour is measured as it shows', () {
      final theme = FlucordTheme.fromPalette(
        FlucordPalette.dark.copyWith(brand: 0x40ffc0cb, danger: 0x40ffb0b0),
      );
      final surfaces = theme.extension<FlucordSurfaceTheme>()!;

      expectReadable(theme, surfaces.link, 4.5);
      expectReadable(theme, surfaces.errorText, 4.5);
      expectReadable(theme, surfaces.focusRing, 3);
    });
  });

  group('the focus ring', () {
    for (final (name, theme) in [
      ('dark', FlucordTheme.dark),
      ('light', FlucordTheme.light),
    ]) {
      test('is 2 px on a focused field and button in $name', () {
        final ring = BorderSide(
          color: theme.extension<FlucordSurfaceTheme>()!.focusRing,
          width: 2,
        );

        expect(theme.inputDecorationTheme.focusedBorder!.borderSide, ring);
        for (final style in [
          theme.iconButtonTheme.style,
          theme.filledButtonTheme.style,
          theme.textButtonTheme.style,
          theme.outlinedButtonTheme.style,
        ]) {
          expect(style!.side!.resolve({WidgetState.focused}), ring);
          expect(style.side!.resolve({}), isNull);
        }
      });
    }
  });
}
