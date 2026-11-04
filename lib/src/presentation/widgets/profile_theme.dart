import 'package:flutter/material.dart';

import '../../domain/discord_rgb.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_theme.dart';

/// Gives [child] the palette a profile's Nitro theme makes, or leaves it in
/// the app's theme when [colors] is null.
///
/// The palette starts from Flucord's own dark or light theme, picked by the
/// gradient's brightness, and never from the theme the app is in: a profile
/// looks the same to everybody. Its backgrounds take the primary colour, so
/// the avatar ring and the status bubble match the top of the gradient.
class ProfileTheme extends StatelessWidget {
  const ProfileTheme({required this.colors, required this.child, super.key});

  final ProfileThemeColors? colors;
  final Widget child;

  static final _dark = FlucordTheme.dark;
  static final _light = FlucordTheme.light;

  @override
  Widget build(BuildContext context) => switch (colors) {
    final colors? => Theme(data: _themeOf(colors), child: child),
    null => child,
  };

  static ThemeData _themeOf(ProfileThemeColors colors) {
    final (:primary, :accent) = _colorsOf(colors);
    final middle = Color.lerp(primary, accent, 0.5)!;
    final base = switch (ThemeData.estimateBrightnessForColor(middle)) {
      Brightness.dark => _dark,
      Brightness.light => _light,
    };
    final surfaces = base.extension<FlucordSurfaceTheme>()!;
    return base.copyWith(
      extensions: [
        surfaces.copyWith(
          rail: primary,
          canvas: primary,
          surface: primary,
          raised: primary,
          inset: primary,
          // Fills sit on the gradient, so they let it show through.
          control: surfaces.text.withValues(alpha: 0.12),
        ),
      ],
    );
  }
}

/// Paints [color] behind [child], or the gradient of [colors] when the
/// profile has a theme.
class ProfileBackdrop extends StatelessWidget {
  const ProfileBackdrop({
    required this.color,
    required this.colors,
    required this.child,
    super.key,
  });

  final Color? color;
  final ProfileThemeColors? colors;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      DecoratedBox(decoration: _decoration(), child: child);

  BoxDecoration _decoration() {
    final theme = colors;
    if (theme == null) return BoxDecoration(color: color);
    final (:primary, :accent) = _colorsOf(theme);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [primary, accent],
      ),
    );
  }
}

({Color primary, Color accent}) _colorsOf(ProfileThemeColors colors) => (
  primary: Color(DiscordRgb(colors.primary).opaque),
  accent: Color(DiscordRgb(colors.accent).opaque),
);
