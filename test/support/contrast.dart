import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

/// The WCAG 2 contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final lighter = max(a.computeLuminance(), b.computeLuminance());
  final darker = min(a.computeLuminance(), b.computeLuminance());
  return (lighter + 0.05) / (darker + 0.05);
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
