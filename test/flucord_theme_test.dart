import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  test('dark theme exposes Discord workspace surface roles', () {
    final theme = FlucordTheme.dark;
    final surfaces = theme.extension<FlucordSurfaceTheme>()!;

    expect(theme.colorScheme.primary, FlucordColors.brand);
    expect(theme.colorScheme.secondary, FlucordColors.success);
    expect(theme.colorScheme.error, FlucordColors.danger);
    expect(surfaces.rail, FlucordColors.darkRail);
    expect(surfaces.canvas, FlucordColors.darkCanvas);
    expect(surfaces.surface, FlucordColors.darkSurface);
    expect(surfaces.raised, FlucordColors.darkRaised);
    expect(surfaces.inset, FlucordColors.darkInset);
    expect(surfaces.control, FlucordColors.darkControl);
    expect(theme.inputDecorationTheme.fillColor, FlucordColors.darkControl);
  });

  test('light theme keeps rail, sidebar, chat, and controls distinct', () {
    final theme = FlucordTheme.light;
    final surfaces = theme.extension<FlucordSurfaceTheme>()!;

    expect(surfaces.rail, FlucordColors.lightRail);
    expect(surfaces.canvas, FlucordColors.lightCanvas);
    expect(surfaces.surface, FlucordColors.lightSurface);
    expect(surfaces.raised, FlucordColors.lightRaised);
    expect(surfaces.inset, FlucordColors.lightInset);
    expect(surfaces.control, FlucordColors.lightControl);
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
      FlucordColors.brand.withValues(alpha: 0.2),
    );
    final filled = theme.filledButtonTheme.style!;
    expect(filled.backgroundColor!.resolve({}), FlucordColors.brand);
    expect(
      filled.backgroundColor!.resolve({WidgetState.pressed}),
      FlucordColors.brandPressed,
    );
    final focused = theme.inputDecorationTheme.focusedBorder!;
    expect(
      (focused as OutlineInputBorder).borderSide.color,
      FlucordColors.brand,
    );
  });

  test('surface roles interpolate without dropping semantic fields', () {
    final dark = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
    final light = FlucordTheme.light.extension<FlucordSurfaceTheme>()!;
    final midpoint = dark.lerp(light, 0.5);

    expect(midpoint.rail, Color.lerp(dark.rail, light.rail, 0.5));
    expect(midpoint.control, Color.lerp(dark.control, light.control, 0.5));
  });
}
