import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// A row in any Flucord menu: a leading mark, a label, and an optional
/// trailing mark.
///
/// Use it in place of [PopupMenuItem] with [PopupMenuButton] or [showMenu].
/// The menu's frame comes from the theme; this draws the row inside it. The
/// row spans the frame, so the menu still opens at the pointer, and its hover
/// is rounded and inset from the frame's edge.
class FlucordMenuItem<T> extends PopupMenuItem<T> {
  const FlucordMenuItem({
    required this.label,
    this.icon,
    this.leading,
    this.trailing,
    this.danger = false,
    super.value,
    super.enabled,
    super.key,
  }) : super(height: rowHeight, child: null);

  static const double rowHeight = 32;

  final String label;

  /// The row's icon. [leading] takes its place for a mark that is not an
  /// icon, such as a status dot.
  final FlucordIconData? icon;
  final Widget? leading;
  final Widget? trailing;

  /// Draws the row in the danger colour, for an action that destroys.
  final bool danger;

  @override
  PopupMenuItemState<T, FlucordMenuItem<T>> createState() =>
      _FlucordMenuItemState<T>();
}

class _FlucordMenuItemState<T>
    extends PopupMenuItemState<T, FlucordMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final item = widget;
    final color = item.danger ? surfaces.errorText : surfaces.text;
    // Icons are muted beside the label, except on a danger row.
    final mark =
        item.leading ??
        (item.icon == null
            ? null
            : FlucordIcon(item.icon!, color: item.danger ? color : null));
    final row = SizedBox(
      height: item.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (mark != null) ...[
              SizedBox.square(dimension: 16, child: Center(child: mark)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.style.copyWith(color: color),
              ),
            ),
            if (item.trailing case final trailing?) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
    return MergeSemantics(
      child: buildSemantics(
        child: IconTheme.merge(
          data: IconThemeData(size: 16, color: surfaces.muted),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: item.enabled ? handleTap : null,
              canRequestFocus: item.enabled,
              mouseCursor: item.mouseCursor,
              borderRadius: FlucordRadius.control,
              child: Opacity(
                opacity: item.enabled ? 1 : FlucordTheme.disabledAlpha,
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line between groups of [FlucordMenuItem]s.
class FlucordMenuDivider extends PopupMenuDivider {
  const FlucordMenuDivider({super.key}) : super(height: 9);
}
