import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// The rail's sizes, shared by every rail so they read as one column.
abstract final class RailMetrics {
  static const width = 64.0;
  static const tile = 40.0;

  /// Space between two tiles, and above and below the divider.
  static const gap = 8.0;

  /// A glyph drawn on a tile, such as the DM or add-server icon.
  static const glyph = 20.0;
}

/// A space's initials, drawn on its tile when it has no icon.
class RailMonogram extends StatelessWidget {
  const RailMonogram(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      style: FlucordTextRole.label.style.copyWith(
        color: FlucordFixedColors.onFill,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// The divider between the home tile and the spaces.
class RailDivider extends StatelessWidget {
  const RailDivider({super.key});

  static const _indent = 16.0;

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: RailMetrics.gap),
    child: Divider(height: 1, indent: _indent, endIndent: _indent),
  );
}

/// The light or dark switch at the foot of a rail.
class RailThemeToggle extends StatelessWidget {
  const RailThemeToggle({
    required this.isDark,
    required this.onPressed,
    super.key,
  });

  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: FlucordIcon(
      isDark ? FlucordIcons.lightTheme : FlucordIcons.darkTheme,
    ),
    tooltip: isDark ? 'Use light theme' : 'Use dark theme',
  );
}

/// The marker on the rail's left edge beside a tile.
enum RailPill {
  none(0),

  /// The space has unread messages.
  unread(8),

  /// The space is open.
  selected(20);

  const RailPill(this.height);

  final double height;
}

/// One tile on a rail: a 40 px square with the large radius, its pill on the
/// rail's left edge, and an optional badge over its bottom right corner.
///
/// A tile with no [color] is outlined rather than filled, for actions such
/// as add server.
class RailTile extends StatefulWidget {
  const RailTile({
    required this.tileKey,
    required this.label,
    required this.onPressed,
    required this.builder,
    this.tooltip,
    this.selected = false,
    this.pill = RailPill.none,
    this.pillKey,
    this.badge,
    this.color,
    this.activeColor,
    this.dimmed = false,
    this.onOpenMenu,
    super.key,
  });

  static const _pillWidth = 4.0;

  /// How far the badge hangs past the tile's bottom right corner.
  static const _badgeOverhang = 4.0;

  static const _hover = Duration(milliseconds: 140);

  /// Sits on the tile's ink, which is what a tap lands on.
  final Key tileKey;

  /// What a screen reader announces.
  final String label;

  /// What the tooltip shows, [label] when null.
  final String? tooltip;

  final VoidCallback? onPressed;

  /// Draws the tile's content. `active` is true while selected or hovered.
  final Widget Function(BuildContext context, bool active) builder;

  final bool selected;
  final RailPill pill;
  final Key? pillKey;
  final Widget? badge;

  /// The fill at rest, or null for an outlined tile.
  final Color? color;

  /// The fill while selected or hovered, [color] when null.
  final Color? activeColor;

  /// Fades the content at rest, for a muted space. The badge stays at full
  /// strength, because a mention outranks a mute.
  final bool dimmed;

  /// Opens the tile's menu at a global position, on a right click.
  final ValueChanged<Offset>? onOpenMenu;

  @override
  State<RailTile> createState() => _RailTileState();
}

class _RailTileState extends State<RailTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final active = widget.selected || _hovered;
    final fill = active ? widget.activeColor ?? widget.color : widget.color;
    final outlined = widget.color == null;
    return Semantics(
      label: widget.label,
      button: widget.onPressed != null,
      enabled: widget.onPressed != null,
      selected: widget.selected,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: SizedBox(
        width: RailMetrics.width,
        height: RailMetrics.tile,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.pill != RailPill.none)
              Positioned(
                left: 0,
                child: SizedBox(
                  key: widget.pillKey,
                  width: RailTile._pillWidth,
                  height: widget.pill.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surfaces.text,
                      borderRadius: BorderRadius.horizontal(
                        right: FlucordRadius.full.topRight,
                      ),
                    ),
                  ),
                ),
              ),
            Tooltip(
              message: widget.tooltip ?? widget.label,
              excludeFromSemantics: true,
              preferBelow: false,
              child: MouseRegion(
                onEnter: (_) {
                  if (widget.onPressed != null) {
                    setState(() => _hovered = true);
                  }
                },
                onExit: (_) => setState(() => _hovered = false),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Material(
                      type: MaterialType.transparency,
                      borderRadius: FlucordRadius.large,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: widget.tileKey,
                        onTap: widget.onPressed,
                        onSecondaryTapDown: widget.onOpenMenu == null
                            ? null
                            : (details) =>
                                  widget.onOpenMenu!(details.globalPosition),
                        borderRadius: FlucordRadius.large,
                        child: AnimatedContainer(
                          duration: RailTile._hover,
                          curve: Curves.easeOut,
                          width: RailMetrics.tile,
                          height: RailMetrics.tile,
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: FlucordRadius.large,
                            border: outlined
                                ? Border.all(color: surfaces.border)
                                : null,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Opacity(
                            opacity: widget.dimmed && !active ? 0.45 : 1,
                            child: widget.builder(context, active),
                          ),
                        ),
                      ),
                    ),
                    if (widget.badge case final badge?)
                      Positioned(
                        right: -RailTile._badgeOverhang,
                        bottom: -RailTile._badgeOverhang,
                        child: badge,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
