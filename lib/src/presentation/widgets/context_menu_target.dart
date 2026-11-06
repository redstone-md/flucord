import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Something with a context menu: a right click, the context-menu key or
/// Shift+F10 calls [onOpen] with the target's own context, to open the menu
/// from, and the pointer's global position for a click or null for a key.
///
/// Focusable so the keyboard reaches the menu too. The keys are bound above
/// the focus, where its key presses pass on their way up; Escape is not
/// bound, so it still reaches whatever binds it higher up. [builder] is told
/// whether the target has the keyboard focus, to draw a ring. That is not
/// the Room's Focused, which is the tile on the Stage.
class ContextMenuTarget extends StatelessWidget {
  const ContextMenuTarget({
    required this.onOpen,
    required this.builder,
    this.onDoubleTap,
    this.focusable = true,
    super.key,
  });

  final void Function(BuildContext context, Offset? position) onOpen;
  final Widget Function(BuildContext context, bool hasFocus) builder;
  final VoidCallback? onDoubleTap;

  /// False when what [builder] draws takes the focus itself, as a button
  /// does: the keys still open the menu while it has the focus, and the
  /// target adds no second stop to Tab.
  final bool focusable;

  @override
  Widget build(BuildContext context) {
    void openByKey() => onOpen(context, null);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): openByKey,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): openByKey,
      },
      child: Focus(
        canRequestFocus: focusable,
        skipTraversal: !focusable,
        child: Builder(
          builder: (context) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (details) =>
                onOpen(context, details.globalPosition),
            onDoubleTap: onDoubleTap,
            child: builder(context, Focus.of(context).hasFocus),
          ),
        ),
      ),
    );
  }
}
