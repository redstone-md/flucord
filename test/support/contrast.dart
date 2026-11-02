import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

/// The WCAG 2 contrast ratio of [foreground] drawn on [background].
///
/// A translucent [foreground] is measured as it shows, mixed with
/// [background].
double contrast(Color foreground, Color background) {
  final shown = Color.alphaBlend(foreground, background).computeLuminance();
  final under = background.computeLuminance();
  return (max(shown, under) + 0.05) / (min(shown, under) + 0.05);
}

/// Expects [foreground] to reach [minimum] on each of the six backgrounds
/// [theme] paints, since a widget can end up on any of them.
///
/// WCAG AA asks 4.5:1 for text and 3:1 for icons and focus rings.
void expectReadable(ThemeData theme, Color? foreground, double minimum) {
  expect(foreground, isNotNull);
  final surfaces = theme.extension<FlucordSurfaceTheme>()!;
  final backgrounds = {
    'rail': surfaces.rail,
    'canvas': surfaces.canvas,
    'surface': surfaces.surface,
    'raised': surfaces.raised,
    'inset': surfaces.inset,
    'control': surfaces.control,
  };
  backgrounds.forEach((name, background) {
    expect(
      contrast(foreground!, background),
      greaterThanOrEqualTo(minimum),
      reason: 'on $name',
    );
  });
}
