import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import 'voice_control.dart';

/// A square icon button in the voice panel or the user panel.
///
/// The icon is muted at rest, full text colour while [active], and the danger
/// colour when it flags a problem such as a muted microphone. [fill] sits
/// behind it; null draws only the hover.
class PanelIconButton extends StatelessWidget {
  const PanelIconButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.size,
    this.fill,
    this.active = false,
    this.danger = false,
    super.key,
  });

  PanelIconButton.control({
    required Key buttonKey,
    required VoiceControl control,
    required double size,
    Color? fill,
    Key? key,
  }) : this(
         buttonKey: buttonKey,
         tooltip: control.tooltip,
         icon: control.icon,
         onPressed: control.onPressed,
         size: size,
         fill: fill,
         active: control.active,
         danger: control.danger,
         key: key,
       );

  final Key buttonKey;
  final String tooltip;
  final FlucordIconData icon;
  final VoidCallback? onPressed;

  /// The button's height, and its width unless a parent stretches it.
  final double size;
  final Color? fill;
  final bool active;
  final bool danger;

  /// The icon on the 28 and 32 px buttons alike.
  static const _iconSize = 16.0;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final colour = onPressed == null
        ? surfaces.muted.withValues(alpha: FlucordTheme.disabledAlpha)
        : danger
        ? surfaces.danger
        : active
        ? surfaces.text
        : surfaces.muted;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: fill ?? Colors.transparent,
        borderRadius: FlucordRadius.control,
        child: InkWell(
          key: buttonKey,
          borderRadius: FlucordRadius.control,
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: FlucordIcon(icon, size: _iconSize, color: colour),
          ),
        ),
      ),
    );
  }
}
