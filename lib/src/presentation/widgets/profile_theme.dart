import 'package:flutter/material.dart';

import '../../domain/discord_rgb.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_theme.dart';

/// Gives [child] the palette a profile's Nitro theme makes, or leaves it in
/// the app's theme when [colors] is null.
///
/// The palette starts from Flucord's own dark or light theme, picked by the
/// primary colour's brightness, and never from the theme the app is in: a
/// profile looks the same to everybody. Its backgrounds take the primary
/// colour under the veil, so the avatar ring and the status bubble match the
/// top of the card. Boxes in it are a thinner veil that lets the gradient
/// through, and lines are faint, as in Discord.
class ProfileTheme extends StatelessWidget {
  const ProfileTheme({required this.colors, required this.child, super.key});

  final ProfileThemeColors? colors;
  final Widget child;

  static final _dark = FlucordTheme.dark;
  static final _light = FlucordTheme.light;

  @override
  Widget build(BuildContext context) => switch (colors) {
    final colors? => Theme(data: _themeOf(_ProfileLook(colors)), child: child),
    null => child,
  };

  static ThemeData _themeOf(_ProfileLook look) {
    final base = switch (look.brightness) {
      Brightness.dark => _dark,
      Brightness.light => _light,
    };
    final surfaces = base.extension<FlucordSurfaceTheme>()!;
    final top = Color.alphaBlend(look.veil, look.primary);
    return base.copyWith(
      // A list replaces every extension, so the others are carried over.
      extensions: [
        ...base.extensions.values,
        surfaces.copyWith(
          rail: top,
          canvas: top,
          surface: top,
          raised: top,
          // Discord's section box: the veil's colour at 45 %.
          inset: look.veil.withValues(alpha: 0.45),
          // Fills sit on the gradient, so they let it show through.
          control: surfaces.text.withValues(alpha: 0.12),
          border: look.line,
        ),
      ],
    );
  }
}

/// Paints [color] behind [child], or Discord's gradient of [colors] when the
/// profile has a theme: the primary colour down to the banner's bottom edge
/// at [bannerHeight], then on to the accent at the bottom, under a veil that
/// leaves [rim] of the bare gradient around it.
class ProfileBackdrop extends StatelessWidget {
  const ProfileBackdrop({
    required this.color,
    required this.colors,
    required this.bannerHeight,
    required this.child,
    this.rim = 0,
    this.radius = BorderRadius.zero,
    super.key,
  });

  final Color? color;
  final ProfileThemeColors? colors;
  final double bannerHeight;

  /// Discord's popout leaves 2 px; the full profile none.
  final double rim;

  /// The outer corners. The veil's are [rim] smaller, so the two stay
  /// parallel.
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = colors;
    if (theme == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: color),
        child: child,
      );
    }
    final look = _ProfileLook(theme);
    final inner = radius - BorderRadius.circular(rim);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: HeldGradient(
          colors: [look.primary, look.accent],
          hold: rim + bannerHeight,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(rim),
        child: DecoratedBox(
          key: const ValueKey('profile-veil'),
          decoration: BoxDecoration(color: look.veil, borderRadius: inner),
          child: ClipRRect(borderRadius: inner, child: child),
        ),
      ),
    );
  }
}

/// A top-to-bottom gradient whose first colour holds for [hold] logical
/// pixels before it turns into the second by the bottom, the way Discord's
/// profile gradient holds its primary colour behind the banner.
final class HeldGradient extends LinearGradient {
  const HeldGradient({required super.colors, required this.hold})
    : assert(colors.length == 2),
      super(begin: Alignment.topCenter, end: Alignment.bottomCenter);

  final double hold;

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) =>
      LinearGradient(
        begin: begin,
        end: end,
        colors: [colors.first, ...colors],
        stops: [0, rect.height <= 0 ? 0 : (hold / rect.height).clamp(0, 1), 1],
      ).createShader(rect, textDirection: textDirection);

  @override
  bool operator ==(Object other) =>
      other is HeldGradient && other.hold == hold && super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, hold);
}

/// The colours a profile theme draws with. The primary colour's brightness
/// picks a dark or a light look, as Discord's popout does.
final class _ProfileLook {
  factory _ProfileLook(ProfileThemeColors colors) {
    final primary = Color(DiscordRgb(colors.primary).opaque);
    return _ProfileLook._(
      primary: primary,
      accent: Color(DiscordRgb(colors.accent).opaque),
      brightness: ThemeData.estimateBrightnessForColor(primary),
    );
  }

  const _ProfileLook._({
    required this.primary,
    required this.accent,
    required this.brightness,
  });

  final Color primary;
  final Color accent;
  final Brightness brightness;

  bool get _dark => brightness == Brightness.dark;

  /// Laid over the gradient behind the content: black at 60 % on a dark
  /// look, Discord's `--profile-gradient-overlay-color`.
  Color get veil =>
      (_dark ? Colors.black : Colors.white).withValues(alpha: 0.6);

  /// The outline and the lines inside: white at 8 % on a dark look.
  Color get line =>
      (_dark ? Colors.white : Colors.black).withValues(alpha: 0.08);
}
