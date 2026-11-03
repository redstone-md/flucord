import 'package:flutter/material.dart';

/// The app's type: one bundled font family and one scale of sizes.
///
/// Every piece of text takes its size from this scale, so the interface has
/// five sizes rather than one per widget. Nothing is under 12 px. The font
/// dial in Accessibility then scales all of them together.
abstract final class FlucordType {
  /// Bundled with the app (see `assets/fonts/golos_text`), so text looks the
  /// same on Windows, macOS and Linux. A system font would exist on one of
  /// them. Its Cyrillic is drawn for interfaces: a `б` never reads as a `6`.
  static const family = 'Golos Text';

  /// Timestamps, badges, counters, section labels and hints. The smallest.
  static const caption = 12.0;

  /// Controls, list rows, buttons and most interface text. The default.
  static const label = 14.0;

  /// Message text and panel headings: what people read at length.
  static const body = 16.0;

  /// Dialog and page titles.
  static const title = 20.0;

  /// The largest text, such as a channel's welcome heading.
  static const display = 24.0;

  static const sizes = [caption, label, body, title, display];

  /// The largest size on the scale that fits in [space], and never under
  /// [caption]. For text drawn to fill a box, such as an avatar's initial.
  static double fitting(double space) =>
      sizes.lastWhere((size) => size <= space, orElse: () => caption);

  /// Material's text roles, each set to a size on the scale.
  ///
  /// Material widgets draw in these roles: a badge in `labelSmall`, helper
  /// text in `bodySmall`, a field in `bodyLarge`. Material's own sizes run
  /// from 11 to 57 px, so without this they would sit off the scale.
  static TextTheme textTheme(TextTheme base) {
    TextStyle? sized(TextStyle? style, double size) =>
        style?.copyWith(fontSize: size);
    return base.copyWith(
      displayLarge: sized(base.displayLarge, display),
      displayMedium: sized(base.displayMedium, display),
      displaySmall: sized(base.displaySmall, display),
      headlineLarge: sized(base.headlineLarge, display),
      headlineMedium: sized(base.headlineMedium, display),
      headlineSmall: sized(base.headlineSmall, display),
      titleLarge: sized(base.titleLarge, title),
      titleMedium: sized(base.titleMedium, body),
      titleSmall: sized(base.titleSmall, label),
      bodyLarge: sized(base.bodyLarge, body),
      bodyMedium: sized(base.bodyMedium, label),
      bodySmall: sized(base.bodySmall, caption),
      labelLarge: sized(base.labelLarge, label),
      labelMedium: sized(base.labelMedium, caption),
      labelSmall: sized(base.labelSmall, caption),
    );
  }
}
