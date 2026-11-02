import 'package:flutter/material.dart';

/// The one dialog frame in the app.
///
/// The barrier, background, corners and title style come from the theme's
/// dialog theme, so every dialog looks the same and an installed theme reaches
/// all of them. Open it with `showDialog`, which takes the barrier from there
/// too. Do not pass a colour or a shape here or at `showDialog`.
///
/// The default form is a title, content and actions, laid out and announced
/// like Material's alert dialog. [FlucordDialog.frame] gives a dialog with a
/// layout of its own, such as settings with a side menu, the same frame.
class FlucordDialog extends StatelessWidget {
  const FlucordDialog({
    this.title,
    this.content,
    this.actions,
    this.maxWidth = _materialMaxWidth,
    super.key,
  }) : child = null,
       maxHeight = null,
       alignment = null,
       insetPadding = null;

  /// The frame alone, with [child] inside it at the size it asks for, within
  /// [maxWidth] and [maxHeight].
  ///
  /// [alignment] and [insetPadding] place a dialog that belongs near what
  /// opened it, such as the inbox under its button.
  const FlucordDialog.frame({
    required Widget this.child,
    this.maxWidth = double.infinity,
    this.maxHeight,
    this.alignment,
    this.insetPadding,
    super.key,
  }) : title = null,
       content = null,
       actions = null;

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final Widget? child;
  final double maxWidth;
  final double? maxHeight;
  final AlignmentGeometry? alignment;
  final EdgeInsets? insetPadding;

  /// The widest Material lets a dialog be.
  static const _materialMaxWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    if (child == null) {
      return AlertDialog(
        title: title,
        content: content,
        actions: actions,
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(minWidth: 280, maxWidth: maxWidth),
      );
    }
    return Dialog(
      alignment: alignment,
      insetPadding: insetPadding,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: child,
      ),
    );
  }
}

/// The title row of a [FlucordDialog.frame]: an optional [icon], the [title]
/// in the dialog title style, and a close button. A null [onClose] shows the
/// button disabled, for a dialog that is busy and must not close.
class FlucordDialogHeader extends StatelessWidget {
  const FlucordDialogHeader({
    required this.title,
    required this.onClose,
    this.icon,
    super.key,
  });

  final String title;
  final VoidCallback? onClose;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon case final icon?) ...[
        Icon(icon, size: 18),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Text(title, style: DialogTheme.of(context).titleTextStyle),
      ),
      IconButton(
        onPressed: onClose,
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Close',
      ),
    ],
  );
}
