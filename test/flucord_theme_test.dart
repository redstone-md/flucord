import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/theme/file_theme_store.dart';
import 'package:flucord/src/domain/flucord_palette.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';

import 'support/contrast.dart';

void main() {
  test('light theme keeps rail, sidebar and chat distinct', () {
    final surfaces = FlucordTheme.light.extension<FlucordSurfaceTheme>()!;

    expect(surfaces.rail, isNot(surfaces.canvas));
    expect(surfaces.surface, isNot(surfaces.canvas));
  });

  test('a slider track shows in both themes', () {
    for (final theme in [FlucordTheme.dark, FlucordTheme.light]) {
      final surfaces = theme.extension<FlucordSurfaceTheme>()!;
      final track = theme.sliderTheme.inactiveTrackColor!;

      for (final background in [surfaces.canvas, surfaces.surface]) {
        expect(
          contrast(track, background),
          greaterThan(1.15),
          reason: '${theme.brightness.name} track on $background',
        );
      }
    }
  });

  test('icon buttons resolve a quiet default and a violet focus', () {
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
      // Bright, so they already read on the near-black backgrounds and are
      // kept as written.
      bodyText: 0xffffff11,
      muted: 0xff000008,
      captionText: 0xffffff12,
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
    expect(surfaces.bodyText, const Color(0xffffff11));
    expect(surfaces.muted, const Color(0xff000008));
    expect(surfaces.captionText, const Color(0xffffff12));
    expect(surfaces.border, const Color(0xff000009));
    expect(surfaces.brand, const Color(0xff00000a));
    expect(surfaces.brandPressed, const Color(0xff00000b));
    expect(surfaces.success, const Color(0xff00000c));
    expect(surfaces.warning, const Color(0xff00000d));
    expect(surfaces.mention, const Color(0xff00000e));
    expect(surfaces.danger, const Color(0xff00000f));
    expect(surfaces.offline, const Color(0xff000010));
  });

  group('the dark palette', () {
    const dark = FlucordPalette.dark;

    test('takes the direction B surfaces', () {
      expect(dark.rail, 0xff08090a);
      expect(dark.canvas, 0xff111113);
      expect(dark.surface, 0xff111113);
      expect(dark.raised, 0xff1b1b1e);
      expect(dark.inset, 0xff0c0c0e);
    });

    test('has four text tiers, brightest first', () {
      expect(dark.text, 0xffeeeef0);
      expect(dark.bodyText, 0xffc8c8ce);
      expect(dark.muted, 0xff8e8e96);
      expect(dark.captionText, 0xff616168);
    });

    test('takes the direction B accent and signal colours', () {
      expect(dark.brand, 0xff8b7cf6);
      expect(dark.danger, 0xffe5484d);
      expect(dark.success, 0xff46a758);
      expect(dark.warning, 0xffe2a336);
    });

    test('draws borders in white at 7%', () {
      final border = Color(dark.border);

      expect(border.a, closeTo(0.07, 0.005));
      expect((border.r, border.g, border.b), (1.0, 1.0, 1.0));
    });
  });

  group('a theme file without the text tiers', () {
    // Written before the tiers existed: it names every other role.
    final older = Map<String, Object?>.of(FlucordPalette.light.toJson())
      ..remove('body_text')
      ..remove('caption_text');

    test('takes the built-in tiers', () {
      final palette = FlucordPalette.fromJson(
        older,
        fallback: FlucordPalette.dark,
      );

      expect(palette.text, FlucordPalette.light.text);
      expect(palette.bodyText, FlucordPalette.dark.bodyText);
      expect(palette.captionText, FlucordPalette.dark.captionText);
    });

    // The built-in tiers are pale; on this light theme they would vanish.
    test('still draws them readable', () {
      final theme = FlucordTheme.fromPalette(FlucordPalette.fromJson(older));
      final surfaces = theme.extension<FlucordSurfaceTheme>()!;

      expectReadable(theme, surfaces.bodyText, 4.5);
      expectReadable(theme, surfaces.captionText, 4.5);
    });

    test('keeps tiers it does name', () {
      final palette = FlucordPalette.fromJson({
        'body_text': '#d0d0d0',
        'caption_text': '#909090',
      });

      expect(palette.bodyText, 0xffd0d0d0);
      expect(palette.captionText, 0xff909090);
    });
  });

  testWidgets('an installed theme paints the primary button in its own text', (
    tester,
  ) async {
    const text = Color(0xfff2e9d8);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.fromPalette(
          FlucordPalette.dark.copyWith(text: text.toARGB32()),
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

    expect(fill('Save'), text);
    expect(fill('Off'), text.withValues(alpha: 0.38));
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
          'message text reaches 4.5:1',
          () => expectContrast(surfaces.bodyText, 4.5),
        );

        test(
          'secondary text reaches 4.5:1',
          () => expectContrast(surfaces.muted, 4.5),
        );

        test(
          'caption text reaches 4.5:1',
          () => expectContrast(surfaces.captionText, 4.5),
        );

        test(
          'a field placeholder reaches 4.5:1',
          () =>
              expectContrast(theme.inputDecorationTheme.hintStyle!.color!, 4.5),
        );

        test(
          'a label on a danger fill reaches 4.5:1',
          () => expect(
            contrast(theme.colorScheme.onError, surfaces.danger),
            greaterThanOrEqualTo(4.5),
          ),
        );

        test(
          'an icon on the accent fill reaches 3:1',
          () => expect(
            contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
            greaterThanOrEqualTo(3),
          ),
        );

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

      expect(surfaces.errorText, const Color(danger));
      expect(surfaces.accentIcon, const Color(brand));
      expect(surfaces.focusRing, const Color(brand));
    });

    test('a pale accent takes a dark label, a strong one keeps white', () {
      final pale = FlucordTheme.fromPalette(
        FlucordPalette.dark.copyWith(brand: 0xffffc0cb),
      ).colorScheme;

      expect(pale.onPrimary, FlucordFixedColors.onLightFill);
      expect(
        FlucordTheme.dark.colorScheme.onPrimary,
        FlucordFixedColors.onFill,
      );
    });

    // Frame B draws links in #A497F8, a lighter tint of the #8B7CF6 accent.
    test('links are a lighter tint of the accent', () {
      final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
      const figma = Color(0xffa497f8);
      int channel(double value) => (value * 255).round();

      for (final (shown, wanted) in [
        (surfaces.link.r, figma.r),
        (surfaces.link.g, figma.g),
        (surfaces.link.b, figma.b),
      ]) {
        expect(channel(shown), closeTo(channel(wanted), 4));
      }
    });

    test('a theme\'s links keep its accent\'s hue, a step lighter', () {
      const brand = Color(0xffffc0cb);
      final surfaces = FlucordTheme.fromPalette(
        FlucordPalette.dark.copyWith(brand: brand.toARGB32()),
      ).extension<FlucordSurfaceTheme>()!;
      final link = HSLColor.fromColor(surfaces.link);
      final accent = HSLColor.fromColor(brand);

      expect(link.hue, closeTo(accent.hue, 2));
      expect(link.lightness, greaterThan(accent.lightness));
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

  group('the type scale', () {
    final text = FlucordTheme.dark.textTheme;

    // Size, line height and weight of each role, as the spec lists them.
    void expectRole(TextStyle? style, double size, double line, int weight) {
      expect(style!.fontSize, size);
      expect(style.fontSize! * style.height!, closeTo(line, 0.01));
      expect(style.fontWeight!.value, weight);
    }

    test('caption is 12/16 regular', () {
      expectRole(text.bodySmall, 12, 16, 400);
      expectRole(text.labelSmall, 12, 16, 400);
    });

    test('label is 13/18, medium on buttons', () {
      expectRole(text.bodyMedium, 13, 18, 400);
      expectRole(text.labelLarge, 13, 18, 500);
    });

    test('body is 14/21 regular', () {
      expectRole(text.bodyLarge, 14, 21, 400);
    });

    test('heading is 14/20 medium', () {
      expectRole(text.titleSmall, 14, 20, 500);
      expectRole(text.titleMedium, 14, 20, 500);
    });

    test('title is 20/26 medium', () {
      expectRole(text.titleLarge, 20, 26, 500);
    });

    test('display is 24/30 medium', () {
      expectRole(text.headlineSmall, 24, 30, 500);
      expectRole(text.displayLarge, 24, 30, 500);
    });

    test('a role sets its line like Figma does, half above and half below', () {
      expect(text.bodyLarge!.leadingDistribution, TextLeadingDistribution.even);
    });

    test('every role is in the app font', () {
      expect(text.bodyLarge!.fontFamily, FlucordType.family);
      expect(text.titleLarge!.fontFamily, FlucordType.family);
    });

    test('the sizes on the scale, smallest first, tags first of all', () {
      expect(FlucordType.sizes, [10, 11, 12, 13, 14, 20, 24]);
    });

    test('text drawn to fill a box is never under the caption', () {
      expect(FlucordType.fitting(11), FlucordType.caption);
      expect(FlucordType.fitting(13.5), FlucordType.label);
    });
  });

  group('the radius scale', () {
    test('runs small 4, control 6, medium 8, large 12 and full', () {
      expect(FlucordRadius.small, BorderRadius.circular(4));
      expect(FlucordRadius.control, BorderRadius.circular(6));
      expect(FlucordRadius.medium, BorderRadius.circular(8));
      expect(FlucordRadius.large, BorderRadius.circular(12));
      expect(FlucordRadius.overlay, BorderRadius.circular(12));
      expect(FlucordRadius.full, BorderRadius.circular(999));
    });

    test('buttons take the control corner', () {
      final theme = FlucordTheme.dark;
      const control = RoundedRectangleBorder(
        borderRadius: FlucordRadius.control,
      );

      expect(theme.iconButtonTheme.style!.shape!.resolve({}), control);
      expect(theme.filledButtonTheme.style!.shape!.resolve({}), control);
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

  group('the shared controls (Figma component sheet)', () {
    final theme = FlucordTheme.dark;
    final surfaces = theme.extension<FlucordSurfaceTheme>()!;

    test('the primary button is light, with the label in the rail colour', () {
      final filled = theme.filledButtonTheme.style!;

      expect(filled.backgroundColor!.resolve({}), surfaces.text);
      expect(filled.foregroundColor!.resolve({}), surfaces.rail);
      expect(filled.minimumSize!.resolve({})!.height, 32);
      expect(
        filled.padding!.resolve({}),
        const EdgeInsets.symmetric(horizontal: 12),
      );
    });

    test('a field is recessed, with a thin border and the control corner', () {
      final input = theme.inputDecorationTheme;
      final enabled = input.enabledBorder! as OutlineInputBorder;

      expect(input.filled, isTrue);
      expect(input.fillColor, surfaces.inset);
      expect(enabled.borderRadius, FlucordRadius.control);
      expect(enabled.borderSide, BorderSide(color: surfaces.border));
    });

    test('a field in error draws a 2 px danger border', () {
      final input = theme.inputDecorationTheme;
      final danger = BorderSide(color: surfaces.danger, width: 2);

      expect(input.errorBorder!.borderSide, danger);
      expect(input.focusedErrorBorder!.borderSide, danger);
    });

    test(
      'a dialog sits on the raised colour with a border and 12 px corners',
      () {
        final dialog = theme.dialogTheme;

        expect(dialog.backgroundColor, surfaces.raised);
        expect(
          dialog.shape,
          RoundedRectangleBorder(
            borderRadius: FlucordRadius.large,
            side: BorderSide(color: surfaces.border),
          ),
        );
        expect(dialog.barrierColor, Colors.black.withValues(alpha: 0.6));
      },
    );

    test('a slider has a 4 px track filled in the accent', () {
      final slider = theme.sliderTheme;

      expect(slider.trackHeight, 4);
      expect(slider.activeTrackColor, surfaces.brand);
      expect(slider.thumbColor, Colors.white);
    });
  });
}
