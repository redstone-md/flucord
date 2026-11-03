import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import 'flucord_button.dart';

/// The one dialog frame in the app.
///
/// The barrier, background, border, corners and title style come from the
/// theme's dialog theme, so every dialog looks the same and an installed
/// theme reaches all of them. Open it with `showDialog`, which takes the
/// barrier from there too. Do not pass a colour or a shape here or at
/// `showDialog`.
///
/// The default form is a [title], an optional [description] under it, an
/// optional [content], and [actions] right-aligned in a footer band. There is
/// no close button: Escape and the Cancel action close it. [onConfirm] is what
/// Enter does, usually the same as the last action.
///
/// [FlucordDialog.frame] gives a dialog with a layout of its own, such as
/// settings with a side menu, the same frame.
class FlucordDialog extends StatelessWidget {
  const FlucordDialog({
    this.title,
    this.description,
    this.content,
    this.actions,
    this.onConfirm,
    this.maxWidth = 440,
    super.key,
  }) : child = null,
       maxHeight = null,
       alignment = null,
       insetPadding = null,
       fullWindow = false;

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
       description = null,
       content = null,
       actions = null,
       onConfirm = null,
       fullWindow = false;

  /// [child] over the whole window on the rail colour, for a screen that
  /// replaces the app while it is open, such as settings.
  const FlucordDialog.fullWindow({required Widget this.child, super.key})
    : title = null,
      description = null,
      content = null,
      actions = null,
      onConfirm = null,
      maxWidth = double.infinity,
      maxHeight = null,
      alignment = null,
      insetPadding = null,
      fullWindow = true;

  final Widget? title;

  /// One or two sentences under the title, in the muted label style. Cut
  /// after five lines.
  final String? description;
  final Widget? content;
  final List<Widget>? actions;

  /// Runs on Enter. Null leaves Enter to the focused control.
  final VoidCallback? onConfirm;
  final Widget? child;
  final double maxWidth;
  final double? maxHeight;
  final AlignmentGeometry? alignment;
  final EdgeInsets? insetPadding;
  final bool fullWindow;

  static const _padding = 20.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    if (fullWindow && child != null) {
      return Dialog.fullscreen(
        backgroundColor: context.surfaces.rail,
        child: child,
      );
    }
    return Dialog(
      alignment: alignment,
      insetPadding: insetPadding,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: child == null ? 280 : 0,
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: child ?? _ConfirmOnEnter(onConfirm: onConfirm, child: _form()),
      ),
    );
  }

  Widget _form() => Builder(
    builder: (context) {
      final dialogTheme = DialogTheme.of(context);
      final actions = this.actions;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(_padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title case final title?)
                    Semantics(
                      namesRoute: true,
                      container: true,
                      child: DefaultTextStyle(
                        style: dialogTheme.titleTextStyle!,
                        child: title,
                      ),
                    ),
                  if (description case final text?) ...[
                    if (title != null) const SizedBox(height: 4),
                    // A description can quote somebody's text, so a long
                    // one is cut short.
                    Text(
                      text,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: dialogTheme.contentTextStyle,
                    ),
                  ],
                  if (content case final content?) ...[
                    if (title != null || description != null)
                      const SizedBox(height: _gap),
                    DefaultTextStyle(
                      style: dialogTheme.contentTextStyle!,
                      child: content,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (actions != null && actions.isNotEmpty)
            FlucordDialogFooter(actions: actions),
        ],
      );
    },
  );
}

/// The band at the foot of a dialog: canvas fill, a line on top, and the
/// actions right-aligned. A plain [TextButton] in it looks like a secondary
/// [FlucordButton], so every dialog's Cancel matches.
class FlucordDialogFooter extends StatelessWidget {
  const FlucordDialogFooter({required this.actions, super.key});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final secondary = FlucordButton.styleOf(
      context,
      FlucordButtonKind.secondary,
    ).merge(Theme.of(context).textButtonTheme.style);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.canvas,
        border: Border(top: BorderSide(color: surfaces.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: TextButtonTheme(
          data: TextButtonThemeData(style: secondary),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ),
      ),
    );
  }
}

/// Runs [onConfirm] when Enter reaches the dialog.
///
/// Key events start at the focused control and bubble up. A dialog with no
/// field to focus would leave focus on its route, above this, so this takes
/// focus itself once any autofocus inside has had its turn.
class _ConfirmOnEnter extends StatefulWidget {
  const _ConfirmOnEnter({required this.onConfirm, required this.child});

  final VoidCallback? onConfirm;
  final Widget child;

  @override
  State<_ConfirmOnEnter> createState() => _ConfirmOnEnterState();
}

class _ConfirmOnEnterState extends State<_ConfirmOnEnter> {
  final _node = FocusNode(debugLabel: 'FlucordDialog', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    // Autofocus is applied in a microtask queued while building, so a
    // microtask queued after the frame runs after it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scheduleMicrotask(() {
        if (mounted && !_node.hasFocus) _node.requestFocus();
      }),
    );
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final confirm = widget.onConfirm;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (confirm == null || event is! KeyDownEvent || !isEnter) {
      return KeyEventResult.ignored;
    }
    confirm();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, onKeyEvent: _onKey, child: widget.child);
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
        Icon(icon, size: 16),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Semantics(
          namesRoute: true,
          child: Text(title, style: DialogTheme.of(context).titleTextStyle),
        ),
      ),
      IconButton(
        onPressed: onClose,
        icon: const FlucordIcon(FlucordIcons.clear, size: 16),
        tooltip: 'Close',
      ),
    ],
  );
}

