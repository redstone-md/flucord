import 'package:flutter/material.dart';

import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// What a [FlucordButton] does, which sets how loud it is.
enum FlucordButtonKind {
  /// The one action a screen or dialog is for. Light, not violet: white on
  /// the accent does not reach 4.5:1.
  primary,

  /// Any other action, such as Cancel.
  secondary,

  /// An action that cannot be undone. Only the button that does it is red.
  danger,

  /// A quiet action with no fill.
  ghost,
}

/// The keys a button can show it answers to.
abstract final class FlucordKeyHint {
  static const escape = 'Esc';
  static const enter = '↵';
}

/// The app's button, in one of four [FlucordButtonKind]s.
///
/// [keyHint] shows the key that also presses it, such as
/// [FlucordKeyHint.escape] on a dialog's Cancel.
class FlucordButton extends StatelessWidget {
  const FlucordButton({
    required this.label,
    required this.onPressed,
    this.kind = FlucordButtonKind.secondary,
    this.keyHint,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final FlucordButtonKind kind;
  final String? keyHint;

  /// The style of [kind], on top of the theme's button style.
  ///
  /// The primary look is the theme's filled button, so a plain
  /// [FilledButton] is a primary button too.
  static ButtonStyle styleOf(BuildContext context, FlucordButtonKind kind) {
    final surfaces = context.surfaces;
    final shared = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      textStyle: WidgetStatePropertyAll(
        FlucordTextRole.label.style.copyWith(fontWeight: FontWeight.w500),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: FlucordRadius.control),
      ),
    );
    return switch (kind) {
      FlucordButtonKind.primary => shared,
      FlucordButtonKind.secondary => shared.copyWith(
        backgroundColor: WidgetStatePropertyAll(surfaces.quietFill),
        foregroundColor: _disabledAware(surfaces.text),
      ),
      FlucordButtonKind.danger => shared.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? surfaces.danger.withValues(alpha: FlucordTheme.disabledAlpha)
              : surfaces.danger,
        ),
        foregroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.onError,
        ),
      ),
      FlucordButtonKind.ghost => shared.copyWith(
        foregroundColor: _disabledAware(surfaces.muted),
      ),
    };
  }

  static WidgetStateProperty<Color> _disabledAware(Color color) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? color.withValues(alpha: FlucordTheme.disabledAlpha)
            : color,
      );

  @override
  Widget build(BuildContext context) {
    final style = styleOf(context, kind);
    final child = keyHint == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 8),
              _KeyHintChip(text: keyHint!, kind: kind),
            ],
          );
    return switch (kind) {
      FlucordButtonKind.primary || FlucordButtonKind.danger => FilledButton(
        style: style,
        onPressed: onPressed,
        child: child,
      ),
      FlucordButtonKind.secondary || FlucordButtonKind.ghost => TextButton(
        style: style,
        onPressed: onPressed,
        child: child,
      ),
    };
  }
}

/// A key drawn as a small chip in the button's own label colour.
class _KeyHintChip extends StatelessWidget {
  const _KeyHintChip({required this.text, required this.kind});

  final String text;
  final FlucordButtonKind kind;

  /// How strongly the chip shows on each kind's fill.
  double get _fillAlpha => switch (kind) {
    FlucordButtonKind.primary => 0.1,
    FlucordButtonKind.danger => 0.18,
    FlucordButtonKind.secondary || FlucordButtonKind.ghost => 0.08,
  };

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final color = style.color ?? context.surfaces.text;
    return ExcludeSemantics(
      child: Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: _fillAlpha),
          borderRadius: FlucordRadius.small,
        ),
        child: Text(
          text,
          style: FlucordTextRole.caption.style.copyWith(color: color),
        ),
      ),
    );
  }
}
