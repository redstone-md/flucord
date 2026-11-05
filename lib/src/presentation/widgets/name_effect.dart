import 'package:flutter/painting.dart';

import '../../theme/flucord_theme.dart';

/// The display name effects this client draws, by
/// `display_name_styles.effect_id`.
///
/// Ids from Discord's mobile client (`DisplayNameEffect.tsx` in
/// Wumpus-Central/discord-mobile-datamining, read 2026-11-04), which matches
/// discord-userdoccers (resources/user.mdx, "Display Name Effect"). How each
/// one looks comes from the web client's stylesheet on discord.com and the
/// mobile client's `UsernameWithEffects.tsx` and `generateColorVariants` in
/// `DisplayNameStylesUtils.tsx`, read the same day. Every effect but solid
/// moves: [NameLook.motion] says how, and `DisplayName` plays it while the
/// motion rule allows.
///
/// Not drawn, so the name stays plain: 8 (gummy, a striped pattern whose
/// letters squash and stretch) and the test ids from 1001.
enum NameEffect {
  /// The first colour.
  solid(1),

  /// All the colours, from the top left to the bottom right.
  gradient(2),

  /// White letters with a coloured outline and a glow in the colour.
  neon(3),

  /// Letters shaded from white at the top to the colour at the bottom, with
  /// a dark outline.
  toon(4),

  /// White letters with a dark outline, over a copy in the colour set a
  /// little lower.
  pop(5),

  /// Drawn as [gradient], as Discord's web docs describe it.
  glow(6),

  /// All the colours from left to right and back to the first. Discord
  /// scrolls it.
  prism(7);

  const NameEffect(this.id);

  final int id;

  static NameEffect? byId(int? id) =>
      values.where((effect) => effect.id == id).firstOrNull;

  /// How a name with this effect and [colors] looks on [surfaces].
  ///
  /// Discord moves a person's colour until it reads on the background
  /// (`useDisplayNameStylesAccessibleColors`); so does this, toward the
  /// theme's text colour, just far enough that the name reads at 4.5:1 on
  /// every surface. A name reads where it meets the surface: by its fill, or
  /// by its outline when it has one, as a white neon name does in a light
  /// theme.
  NameLook look(List<int> colors, FlucordSurfaceTheme surfaces) => _lookIn([
    for (final color in colors)
      FlucordTheme.towardText(
        Color(color),
        text: surfaces.text,
        backgrounds: surfaces.backgrounds,
        reads: (shown, background) => _lookIn([shown]).readsOn(background),
      ),
  ]);

  /// The look of the effect in [colors]. The effects in one colour take the
  /// first.
  NameLook _lookIn(List<Color> colors) {
    final main = colors.first;
    final hsl = HSLColor.fromColor(main);
    Color lightness(double value) =>
        hsl.withLightness(value.clamp(0, 1)).toColor();
    final l = hsl.lightness;
    return switch (this) {
      solid => NameLook(fill: [main]),
      gradient || glow => NameLook(
        fill: colors,
        fillFrom: Alignment.topLeft,
        fillTo: Alignment.bottomRight,
        motion: NameMotion.sway,
      ),
      prism => NameLook(
        fill: colors,
        repeatsFirst: true,
        motion: NameMotion.scroll,
      ),
      neon => NameLook(
        fill: const [FlucordFixedColors.onFill],
        outline: hsl
            .withSaturation((hsl.saturation * 1.2).clamp(0, 1))
            .withLightness((l + 0.1).clamp(0, 0.6))
            .toColor(),
        outlinePixels: 1,
        glow: main,
        motion: NameMotion.pulse,
      ),
      toon => NameLook(
        fill: [
          FlucordFixedColors.onFill,
          lightness(l * 1.6),
          lightness(l * 1.2),
          main,
        ],
        fillFrom: Alignment.topCenter,
        fillTo: Alignment.bottomCenter,
        outline: lightness((l * 0.4).clamp(0.12, 1)),
        outlinePixels: 1.6,
        motion: NameMotion.bounce,
      ),
      pop => NameLook(
        fill: const [FlucordFixedColors.onFill],
        outline: lightness(l * 0.2),
        outlinePixels: 1.2,
        drop: main,
        motion: NameMotion.lift,
      ),
    };
  }
}

/// What a name is drawn with: its fill, and what an effect adds around it.
final class NameLook {
  const NameLook({
    required this.fill,
    this.fillFrom = Alignment.centerLeft,
    this.fillTo = Alignment.centerRight,
    this.repeatsFirst = false,
    this.outline,
    this.outlinePixels = 0,
    this.glow,
    this.drop,
    this.motion = NameMotion.none,
  });

  /// One colour, or the stops of a gradient from [fillFrom] to [fillTo].
  final List<Color> fill;
  final Alignment fillFrom;
  final Alignment fillTo;

  /// Whether the gradient ends on its first colour again.
  final bool repeatsFirst;

  /// A line around each letter, under the fill.
  final Color? outline;
  final double outlinePixels;

  /// A soft light around the letters.
  final Color? glow;

  /// A copy of the name in this colour, outlined in it too, set lower by
  /// the outline's width, behind the name. The mobile client's numbers; the
  /// web client's copy sits 0.08 em lower and has no outline of its own,
  /// which leaves under a pixel of it showing at the sizes of a list.
  final Color? drop;

  /// How the look moves over time.
  final NameMotion motion;

  /// The outline's width at [fontSize]: Discord's pixels plus 0.04 em.
  double outlineWidth(double fontSize) => outlinePixels + 0.04 * fontSize;

  /// The glow's blur at [fontSize]: 4 px plus 0.12 em.
  static double glowBlur(double fontSize) => 4 + 0.12 * fontSize;

  /// The colours of the gradient, in order.
  List<Color> get stops => [...fill, if (repeatsFirst) fill.first];

  /// Whether the name stands out from [background] by its fill or its
  /// outline.
  bool readsOn(Color background) {
    bool reads(Color color) =>
        FlucordTheme.contrast(color, background) >= FlucordTheme.textContrast;
    final outline = this.outline;
    return fill.every(reads) || (outline != null && reads(outline));
  }
}

/// How a name look moves, once per [period]. Discord's effects move like
/// this; the timings are this client's.
enum NameMotion {
  /// Still.
  none(Duration.zero),

  /// The gradient slides across the letters and back.
  sway(Duration(seconds: 4)),

  /// The gradient slides across the letters, around and around.
  scroll(Duration(seconds: 3)),

  /// The glow breathes in and out.
  pulse(Duration(seconds: 2)),

  /// The letters hop up and settle.
  bounce(Duration(milliseconds: 1600)),

  /// The copy behind the letters sinks a little and comes back.
  lift(Duration(seconds: 2));

  const NameMotion(this.period);

  final Duration period;

  /// Where in its period the motion is at [time], from 0 to 1.
  double phaseAt(Duration time) => period == Duration.zero
      ? 0
      : (time.inMicroseconds % period.inMicroseconds) / period.inMicroseconds;
}
