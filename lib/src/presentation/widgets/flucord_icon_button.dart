import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import 'voice_control.dart';

/// The app's icon button: a square, 28 px unless told otherwise, around a
/// 16 px icon, with the control radius unless told otherwise. Hover, press, focus and the disabled
/// shade come from the theme.
///
/// [selected] draws the icon in the text colour while what it opens is
/// showing, such as the member list behind the members button. With no
/// [fill] of its own, a selected button takes the quiet fill.
class FlucordIconButton extends StatelessWidget {
  const FlucordIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.danger = false,
    this.byServer = false,
    this.color,
    this.fill,
    this.dimension = size,
    this.borderRadius = FlucordRadius.control,
    super.key,
  });

  /// A voice control, as the voice panel and the user panel draw it.
  FlucordIconButton.control({
    required VoiceControl control,
    double dimension = size,
    Color? fill,
    Key? key,
  }) : this(
         icon: control.icon,
         tooltip: control.tooltip,
         onPressed: control.onPressed,
         selected: control.active,
         danger: control.danger,
         byServer: control.byServer,
         fill: fill,
         dimension: dimension,
         key: key,
       );

  static const size = 28.0;
  static const _serverFillAlpha = 0.2;
  static const iconSize = 16.0;

  /// The 28 px square, for an icon button this class does not draw, such as
  /// a [PopupMenuButton]'s. Pair it with [iconSize].
  static final squareStyle = IconButton.styleFrom(
    fixedSize: const Size.square(size),
    minimumSize: const Size.square(size),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  final FlucordIconData icon;
  final String tooltip;

  /// Null draws the button disabled.
  final VoidCallback? onPressed;
  final bool selected;

  /// Draws the icon in the danger colour, for a state the person should
  /// notice, such as a muted microphone.
  final bool danger;

  /// Fills the button in the danger colour too, for a state a moderator
  /// holds, such as a server mute.
  final bool byServer;

  /// An icon colour that means something, such as the accent on Send. Null
  /// keeps the theme's muted icon, which brightens on hover.
  final Color? color;

  /// The colour behind the icon at all times. Null draws only the hover,
  /// and the quiet fill while [selected].
  final Color? fill;

  /// The button's height, and its width unless a parent stretches it.
  final double dimension;

  /// The corners of the hover, the focus ring and [fill]. A button that sits
  /// among pills, such as "Add role" after role chips, is a pill too.
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final iconColor = danger ? surfaces.danger : color;
    final background =
        fill ??
        (byServer
            ? surfaces.danger.withValues(alpha: _serverFillAlpha)
            : selected
            ? surfaces.quietFill
            : null);
    final button = IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      isSelected: selected,
      iconSize: iconSize,
      style: squareStyle.copyWith(
        fixedSize: WidgetStatePropertyAll(Size.square(dimension)),
        minimumSize: WidgetStatePropertyAll(Size.square(dimension)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: borderRadius),
        ),
        foregroundColor: selected && iconColor == null
            ? WidgetStatePropertyAll(surfaces.text)
            : null,
      ),
      icon: FlucordIcon(icon, color: iconColor),
    );
    if (background == null) return button;
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: borderRadius),
      child: button,
    );
  }
}
