import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';
import 'theme_scope.dart';
import 'user_settings_scope.dart';

/// The theme navigation draws in: the server rail, the channel sidebar and
/// the frame around the canvas card.
///
/// It is the app's theme, unless the account asks for a dark sidebar on the
/// built-in light palette. Then all navigation draws in the dark palette and
/// the canvas stays light. An installed theme is never overridden: its author
/// picked the panel colours on purpose.
class NavigationTheme extends StatelessWidget {
  const NavigationTheme({required this.child, super.key});

  final Widget child;

  static final _dark = FlucordTheme.dark;

  /// The navigation's surfaces, for a part of it drawn outside a
  /// [NavigationTheme], such as the frame around the canvas card.
  static FlucordSurfaceTheme surfacesOf(BuildContext context) =>
      _isDark(context)
      ? _dark.extension<FlucordSurfaceTheme>()!
      : context.surfaces;

  // Reads the account setting, so a change from any device repaints.
  static bool _isDark(BuildContext context) =>
      UserSettingsScope.appearanceOf(context).drawsDarkSidebar &&
      Theme.of(context).brightness == Brightness.light &&
      ThemeScope.maybeOf(context)?.selected == null;

  @override
  Widget build(BuildContext context) =>
      _isDark(context) ? Theme(data: _dark, child: child) : child;
}
