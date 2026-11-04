import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
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
/// optional [content], and a footer band. There is no close button: Escape
/// and Cancel close it. A dialog that asks for something gives a [confirm]:
/// the footer then holds Cancel with the Esc hint, any [actions], and the
/// confirming button last with the Enter hint, and Enter presses it. A
/// dialog with no [confirm] lists its own [actions], such as a lone
/// [FlucordDialogCancel].
///
/// [FlucordDialog.frame] gives a dialog with a layout of its own, such as
/// settings with a side menu, the same frame.
class FlucordDialog extends StatelessWidget {
  const FlucordDialog({
    this.title,
    this.description,
    this.content,
    this.actions,
    this.confirm,
    this.cancelEnabled = true,
    this.maxWidth = 440,
    super.key,
  }) : child = null,
       maxHeight = null,
       alignment = null,
       insetPadding = null,
       fullWindow = false;

  /// The frame with [child] inside it at the size it asks for, within
  /// [maxWidth] and [maxHeight]. [actions] and [confirm] add the same footer
  /// as the default form, under [child].
  ///
  /// [alignment] and [insetPadding] place a dialog that belongs near what
  /// opened it, such as the inbox under its button.
  const FlucordDialog.frame({
    required Widget this.child,
    this.actions,
    this.confirm,
    this.cancelEnabled = true,
    this.maxWidth = double.infinity,
    this.maxHeight,
    this.alignment,
    this.insetPadding,
    super.key,
  }) : title = null,
       description = null,
       content = null,
       fullWindow = false;

  /// [child] over the whole window on the rail colour, for a screen that
  /// replaces the app while it is open, such as settings.
  const FlucordDialog.fullWindow({required Widget this.child, super.key})
    : title = null,
      description = null,
      content = null,
      actions = null,
      confirm = null,
      cancelEnabled = true,
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

  /// Footer buttons. With a [confirm] they sit between Cancel and it.
  final List<Widget>? actions;

  /// The action the dialog is for, if it asks for one.
  final FlucordDialogConfirm? confirm;

  /// False disables Cancel, for a dialog busy with work it must finish.
  final bool cancelEnabled;
  final Widget? child;
  final double maxWidth;
  final double? maxHeight;
  final AlignmentGeometry? alignment;
  final EdgeInsets? insetPadding;
  final bool fullWindow;

  static const _padding = 20.0;

  /// The top padding above a dialog's title. The font leaves room above its
  /// capitals, so the title starts that much higher and its capitals sit as
  /// far from the top as the text sits from the side.
  static final titleTop =
      _padding - FlucordType.roomAboveCapitals(FlucordTextRole.heading);
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
        child: _withFooter(child ?? _form()),
      ),
    );
  }

  /// [body] over the footer, with Enter wired to [confirm]. A frame with no
  /// footer is [body] alone.
  Widget _withFooter(Widget body) {
    final actions = _footerActions();
    if (child != null && actions.isEmpty) return body;
    return _ConfirmOnEnter(
      onConfirm: confirm?.onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(child: body),
          if (actions.isNotEmpty) FlucordDialogFooter(actions: actions),
        ],
      ),
    );
  }

  Widget _form() => Builder(
    builder: (context) {
      final dialogTheme = DialogTheme.of(context);
      return SingleChildScrollView(
        padding: title == null
            ? const EdgeInsets.all(_padding)
            : EdgeInsets.fromLTRB(_padding, titleTop, _padding, _padding),
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
      );
    },
  );

  List<Widget> _footerActions() {
    final confirm = this.confirm;
    if (confirm == null) return actions ?? const [];
    return [
      FlucordDialogCancel(enabled: cancelEnabled),
      ...?actions,
      FlucordButton(
        key: confirm.key,
        label: confirm.label,
        kind: confirm.kind,
        keyHint: FlucordKeyHint.enter,
        onPressed: confirm.onPressed,
      ),
    ];
  }
}

/// The action a [FlucordDialog] is for: the last button in its footer, with
/// the Enter hint. Enter presses it while [onPressed] is set.
@immutable
final class FlucordDialogConfirm {
  const FlucordDialogConfirm({
    required this.label,
    required this.onPressed,
    this.kind = FlucordButtonKind.primary,
    this.key,
  });

  final String label;

  /// Null disables the button and Enter.
  final VoidCallback? onPressed;

  /// Primary, or danger for an action that cannot be undone.
  final FlucordButtonKind kind;

  /// The button's key.
  final Key? key;
}

/// A dialog's Cancel: a secondary button with the Esc hint that closes the
/// dialog with no answer, as Escape does.
class FlucordDialogCancel extends StatelessWidget {
  const FlucordDialogCancel({
    this.label = 'Cancel',
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => FlucordButton(
    label: label,
    keyHint: FlucordKeyHint.escape,
    onPressed: enabled ? () => Navigator.of(context).pop() : null,
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
        // The same gap on every side, the dialog's corner less a button's,
        // so the last button's corner shares the dialog's centre.
        padding: EdgeInsets.all(
          FlucordRadius.overlay.bottomRight.x -
              FlucordRadius.control.bottomRight.x,
        ),
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
/// focus itself once any autofocus inside has had its turn. Enter stays with
/// a focused control that has its own use for it: a button presses itself
/// and a field of several lines starts a new line. Only a one-line field
/// hands it on.
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
    if (confirm == null ||
        event is! KeyDownEvent ||
        !isEnter ||
        _focusUsesEnter) {
      return KeyEventResult.ignored;
    }
    confirm();
    return KeyEventResult.handled;
  }

  bool get _focusUsesEnter {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus == _node) return false;
    final field = focus.context?.findAncestorWidgetOfExactType<EditableText>();
    return field == null || field.maxLines != 1;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, onKeyEvent: _onKey, child: widget.child);
}

/// The title of a [FlucordDialog.frame], in the dialog title style. There
/// is no close button: Escape closes the dialog.
class FlucordDialogHeader extends StatelessWidget {
  const FlucordDialogHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    namesRoute: true,
    child: Text(title, style: DialogTheme.of(context).titleTextStyle),
  );
}
