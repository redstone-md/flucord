import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// A row that closes the menu and then does [action], disabled when it is
/// null. The row answers with its action, so a menu built of these needs no
/// list of choices to switch on: call what [showMenu] returns.
FlucordMenuItem<VoidCallback> flucordMenuAction(
  String key,
  String label,
  FlucordIconData icon,
  VoidCallback? action, {
  bool danger = false,
}) => FlucordMenuItem(
  key: ValueKey(key),
  value: action,
  icon: icon,
  label: label,
  danger: danger,
  enabled: action != null,
);

/// A row in any Flucord menu: a leading mark, a label, and an optional
/// trailing mark.
///
/// Use it in place of [PopupMenuItem] with [PopupMenuButton] or [showMenu].
/// The menu's frame comes from the theme; this draws the row inside it. The
/// row spans the frame, so the menu still opens at the pointer, and its hover
/// is rounded and inset from the frame's edge.
class FlucordMenuItem<T> extends PopupMenuEntry<T> {
  const FlucordMenuItem({
    required this.label,
    this.value,
    this.icon,
    this.leading,
    this.trailing,
    this.danger = false,
    this.enabled = true,
    super.key,
  });

  static const double rowHeight = 32;

  /// How far the row's hover sits in from the menu's edge.
  static const double inset = 4;

  final String label;

  /// What the menu returns when this row is chosen.
  final T? value;

  /// The row's icon. [leading] takes its place for a mark that is not an
  /// icon, such as a status dot.
  final FlucordIconData? icon;
  final Widget? leading;
  final Widget? trailing;

  /// Draws the row in the danger colour, for an action that destroys.
  final bool danger;

  /// A disabled row is faded and cannot be chosen.
  final bool enabled;

  @override
  double get height => rowHeight;

  @override
  bool represents(T? value) => value == this.value;

  @override
  State<FlucordMenuItem<T>> createState() => _FlucordMenuItemState<T>();
}

class _FlucordMenuItemState<T> extends State<FlucordMenuItem<T>> {
  void _choose() => Navigator.pop<T>(context, widget.value);

  @override
  Widget build(BuildContext context) {
    final item = widget;
    final color = item.danger ? context.surfaces.errorText : null;
    // Icons are muted beside the label, except on a danger row.
    return _MenuRow(
      label: item.label,
      height: item.height,
      color: color,
      leading:
          item.leading ??
          (item.icon == null ? null : FlucordIcon(item.icon!, color: color)),
      trailing: item.trailing,
      enabled: item.enabled,
      role: SemanticsRole.menuItem,
      onTap: _choose,
    );
  }
}

/// A [FlucordMenuItem] that holds a switch: choosing it flips the box at its
/// end and leaves the menu open, so several can be set in one visit.
///
/// The row keeps its own value while the menu is open. A menu's rows are
/// built once, so a value read from outside would not move.
class FlucordMenuCheckbox<T> extends PopupMenuEntry<T> {
  const FlucordMenuCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;

  /// Whether the box is ticked when the menu opens.
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  double get height => FlucordMenuItem.rowHeight;

  @override
  bool represents(T? value) => false;

  @override
  State<FlucordMenuCheckbox<T>> createState() => _FlucordMenuCheckboxState<T>();
}

class _FlucordMenuCheckboxState<T> extends State<FlucordMenuCheckbox<T>> {
  late bool _value = widget.value;

  void _flip() {
    setState(() => _value = !_value);
    widget.onChanged(_value);
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return _MenuRow(
      label: widget.label,
      height: widget.height,
      checked: _value,
      role: SemanticsRole.menuItemCheckbox,
      onTap: _flip,
      trailing: SizedBox.square(
        dimension: 18,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _value ? surfaces.brand : null,
            border: _value ? null : Border.all(color: surfaces.muted, width: 2),
            borderRadius: FlucordRadius.small,
          ),
          child: _value
              ? const FlucordIcon(
                  FlucordIcons.check,
                  size: 14,
                  color: FlucordFixedColors.onFill,
                )
              : null,
        ),
      ),
    );
  }
}

/// A menu row with a label, the value as a whole percentage, and a slider
/// under them. Moving the slider leaves the menu open.
///
/// [mark] draws a short line on the track at that value, such as the normal
/// level on a slider that can go past it. Like [FlucordMenuCheckbox], the row
/// keeps its own value while the menu is open.
class FlucordMenuSlider<T> extends PopupMenuEntry<T> {
  const FlucordMenuSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 1,
    this.mark,
    super.key,
  });

  static const double rowHeight = 60;

  final String label;

  /// The value when the menu opens, from 0 to [max].
  final double value;
  final ValueChanged<double> onChanged;
  final double max;
  final double? mark;

  @override
  double get height => rowHeight;

  @override
  bool represents(T? value) => false;

  @override
  State<FlucordMenuSlider<T>> createState() => _FlucordMenuSliderState<T>();
}

class _FlucordMenuSliderState<T> extends State<FlucordMenuSlider<T>> {
  /// The slider's side padding: the thumb's radius, so the thumb stays
  /// inside the row at both ends and the track runs edge to edge between.
  static const double _trackInset = 7;

  late double _value = widget.value.clamp(0, widget.max);

  void _change(double value) {
    setState(() => _value = value);
    widget.onChanged(value);
  }

  static String _percent(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final mark = widget.mark;
    return SizedBox(
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlucordTextRole.label.style.copyWith(
                      color: surfaces.text,
                    ),
                  ),
                ),
                Text(
                  _percent(_value),
                  style: FlucordTextRole.caption.style.copyWith(
                    color: surfaces.muted,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Under the slider, so the thumb covers it when the value
                  // sits on it. Inset one pixel less than the track, so the
                  // line's centre lands where the thumb's would.
                  if (mark != null)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _trackInset - 1,
                        ),
                        child: Align(
                          alignment: Alignment(mark / widget.max * 2 - 1, 0),
                          child: Container(
                            key: const ValueKey('flucord-menu-slider-mark'),
                            width: 2,
                            height: 12,
                            decoration: BoxDecoration(
                              color: surfaces.muted,
                              borderRadius: FlucordRadius.small,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Slider(
                    value: _value,
                    max: widget.max,
                    // Whole percents, which is what the label shows.
                    divisions: (widget.max * 100).round(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: _trackInset,
                    ),
                    semanticFormatterCallback: _percent,
                    onChanged: _change,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What every Flucord menu row draws: an optional leading mark, a label, an
/// optional trailing mark, and a rounded hover inset from the menu's edge.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.height,
    required this.role,
    required this.onTap,
    this.leading,
    this.trailing,
    this.color,
    this.enabled = true,
    this.checked,
  });

  final String label;
  final double height;
  final SemanticsRole role;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;

  /// The label's colour, the theme's text colour when null.
  final Color? color;
  final bool enabled;

  /// Whether a checkbox row is ticked; null for a row without one.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final mark = leading;
    final row = SizedBox(
      height: height,
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
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.style.copyWith(
                  color: color ?? surfaces.text,
                ),
              ),
            ),
            if (trailing case final trailing?) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
    return MergeSemantics(
      child: Semantics(
        role: role,
        enabled: enabled,
        button: checked == null,
        checked: checked,
        child: IconTheme.merge(
          data: IconThemeData(size: 16, color: surfaces.muted),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FlucordMenuItem.inset,
            ),
            // The row takes the overlay radius less its inset, so the two
            // corners stay parallel.
            child: InkWell(
              onTap: enabled ? onTap : null,
              canRequestFocus: enabled,
              borderRadius: FlucordRadius.large,
              child: Opacity(
                opacity: enabled ? 1 : FlucordTheme.disabledAlpha,
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
