import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_button.dart';
import 'flucord_controls.dart';
import 'flucord_dialog.dart';
import 'flucord_icon_button.dart';

/// One page in the settings navigation.
final class SettingsNavEntry {
  const SettingsNavEntry({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.key,
    this.compactKey,
  });

  final String label;
  final FlucordIconData icon;
  final bool selected;
  final VoidCallback onPressed;

  /// The key of the row in the side column.
  final Key? key;

  /// The key of the tab in the strip a narrow window shows instead. Defaults
  /// to [key].
  final Key? compactKey;
}

/// A run of [SettingsNavEntry]s under an optional [heading].
final class SettingsNavGroup {
  const SettingsNavGroup({required this.entries, this.heading});

  final String? heading;
  final List<SettingsNavEntry> entries;
}

/// The settings screen: the whole window, with the navigation on the left in
/// the rail colour and the page in the same inset card as the chat.
///
/// The card's top bar holds the page [title] and the close button. [body] is
/// the page itself and scrolls on its own. Below [compactWidth] the side
/// column becomes a strip of tabs above the card.
class SettingsLayout extends StatelessWidget {
  const SettingsLayout({
    required this.groups,
    required this.title,
    required this.body,
    this.busy = false,
    this.compactWidth = 720,
    this.closeKey,
    this.stripKey,
    super.key,
  });

  final List<SettingsNavGroup> groups;
  final String title;
  final Widget body;

  /// Shows a small spinner beside the close button while a change is saved.
  final bool busy;
  final double compactWidth;
  final Key? closeKey;

  /// The key of the narrow window's strip of tabs.
  final Key? stripKey;

  static const navigationWidth = 240.0;

  @override
  Widget build(BuildContext context) => FlucordDialog.fullWindow(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final card = _Card(
          title: title,
          busy: busy,
          closeKey: closeKey,
          body: body,
        );
        if (constraints.maxWidth < compactWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Strip(groups: groups, stripKey: stripKey),
              Expanded(child: card),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: navigationWidth,
              child: _Navigation(groups: groups),
            ),
            Expanded(child: card),
          ],
        );
      },
    ),
  );
}

class _Navigation extends StatelessWidget {
  const _Navigation({required this.groups});

  final List<SettingsNavGroup> groups;

  // A short, fixed list: built whole rather than lazily, so every row exists
  // and can be scrolled to.
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) const SizedBox(height: 16),
          if (group.heading case final heading?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text(
                heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.caption.style.copyWith(
                  color: context.surfaces.captionText,
                ),
              ),
            ),
          for (final entry in group.entries) _NavigationRow(entry: entry),
        ],
      ],
    ),
  );
}

class _NavigationRow extends StatelessWidget {
  const _NavigationRow({required this.entry});

  final SettingsNavEntry entry;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final color = entry.selected ? surfaces.text : surfaces.muted;
    return Semantics(
      selected: entry.selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: entry.key,
          onTap: entry.onPressed,
          borderRadius: FlucordRadius.control,
          child: Ink(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: entry.selected ? surfaces.quietFill : null,
              borderRadius: FlucordRadius.control,
            ),
            child: Row(
              children: [
                FlucordIcon(entry.icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlucordTextRole.label.style.copyWith(
                      color: color,
                      fontWeight: entry.selected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.groups, required this.stripKey});

  final List<SettingsNavGroup> groups;
  final Key? stripKey;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: SingleChildScrollView(
      key: stripKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          for (final group in groups)
            for (final entry in group.entries)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: FlucordTab(
                  key: entry.compactKey ?? entry.key,
                  label: entry.label,
                  selected: entry.selected,
                  onPressed: entry.onPressed,
                ),
              ),
        ],
      ),
    ),
  );
}

/// The page: the inset card with its top bar and the scrolling body.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.busy,
    required this.closeKey,
    required this.body,
  });

  final String title;
  final bool busy;
  final Key? closeKey;
  final Widget body;

  static const _closeInset = 16.0;
  static const _spinnerSize = 16.0;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 8, 8),
      // A Material, not a coloured box, so rows inside draw their ink on it.
      child: Material(
        color: surfaces.canvas,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: FlucordRadius.large,
          side: BorderSide(color: surfaces.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 64,
              child: Padding(
                // The close button keeps the same 16 from the top as from
                // the side, and the title sits on the button's centre line.
                padding: const EdgeInsetsDirectional.fromSTEB(
                  40,
                  _closeInset,
                  _closeInset,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        height: FlucordIconButton.size,
                        alignment: AlignmentDirectional.centerStart,
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlucordTextRole.title.style.copyWith(
                              color: surfaces.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (busy)
                      const Padding(
                        // Centred on the close button beside it.
                        padding: EdgeInsetsDirectional.fromSTEB(
                          0,
                          (FlucordIconButton.size - _spinnerSize) / 2,
                          12,
                          0,
                        ),
                        child: SizedBox.square(
                          dimension: _spinnerSize,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    _CloseButton(buttonKey: closeKey),
                  ],
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// A 28 px square close button with "Esc" under it, as the settings top bar
/// draws it.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.buttonKey});

  final Key? buttonKey;

  static const _hintGap = 2.0;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final hint = FlucordTextRole.caption.style.copyWith(
      color: surfaces.captionText,
    );
    // As wide as the button, so the button's edge is the bar's edge. The
    // hint is wider than the button and centres under it.
    return SizedBox(
      width: FlucordIconButton.size,
      height: FlucordIconButton.size + _hintGap + hint.fontSize! * hint.height!,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            key: buttonKey,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            iconSize: FlucordIconButton.iconSize,
            style: FlucordIconButton.squareStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(surfaces.quietFill),
            ),
            icon: FlucordIcon(FlucordIcons.clear, color: surfaces.text),
          ),
          Positioned(
            top: FlucordIconButton.size + _hintGap,
            left: -FlucordIconButton.size,
            right: -FlucordIconButton.size,
            child: ExcludeSemantics(
              child: Text(
                FlucordKeyHint.escape,
                textAlign: TextAlign.center,
                style: hint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
