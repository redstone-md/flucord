import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';

/// The app's icon button: a 28 px square around a 16 px icon, with the
/// control radius. Hover, press and focus come from the theme.
///
/// [selected] fills it while what it opens is showing, such as the member
/// list behind the members button.
class FlucordIconButton extends StatelessWidget {
  const FlucordIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.color,
    super.key,
  });

  static const size = 28.0;
  static const iconSize = 16.0;

  /// The fill behind a selected button.
  static const _selectedAlpha = 0.06;

  final FlucordIconData icon;
  final String tooltip;

  /// Null draws the button disabled.
  final VoidCallback? onPressed;
  final bool selected;

  /// An icon colour that means something, such as danger on a hang-up. Null
  /// keeps the theme's muted icon, which brightens on hover.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final button = IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      isSelected: selected,
      constraints: const BoxConstraints.tightFor(width: size, height: size),
      padding: EdgeInsets.zero,
      iconSize: iconSize,
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: selected && color == null
            ? WidgetStatePropertyAll(surfaces.text)
            : null,
      ),
      icon: FlucordIcon(icon, color: color),
    );
    if (!selected) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.text.withValues(alpha: _selectedAlpha),
        borderRadius: FlucordRadius.control,
      ),
      child: button,
    );
  }
}
