import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/quick_switcher_catalog.dart';
import '../domain/chat_models.dart';
import 'conversation_pane.dart';
import 'widgets/quick_switcher.dart';

extension ShellKeyboardWidget on Widget {
  Widget withShellKeyboard({
    required ChatWorkspace workspace,
    required ValueChanged<QuickSwitcherDestination> onOpenDestination,
  }) => ShellKeyboard(
    workspace: workspace,
    onOpenDestination: onOpenDestination,
    child: this,
  );
}

/// The app's keyboard, for keys that work wherever the focus is in the shell.
///
/// Holds the one [Shortcuts] map, and sends a printable key pressed outside a
/// text field to the composer. Sits below the app's routes, so a dialog or a
/// menu keeps its keys to itself.
class ShellKeyboard extends StatefulWidget {
  const ShellKeyboard({
    required this.workspace,
    required this.onOpenDestination,
    required this.child,
    super.key,
  });

  final ChatWorkspace workspace;
  final ValueChanged<QuickSwitcherDestination> onOpenDestination;
  final Widget child;

  /// The key the conversation pane under this keyboard must use, so the keys
  /// can reach it.
  static GlobalKey<ConversationPaneState>? paneKeyOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ShellKeyboardScope>()?.paneKey;

  @override
  State<ShellKeyboard> createState() => _ShellKeyboardState();
}

class _ShellKeyboardState extends State<ShellKeyboard> {
  final GlobalKey<ConversationPaneState> _paneKey = GlobalKey();
  late final Map<ShortcutActivator, Intent> _shortcuts = _buildShortcuts();
  bool _switcherOpen = false;

  ConversationPaneState? get _pane => _paneKey.currentState;

  /// The same table as Discord's: Ctrl on Windows and Linux is Cmd on macOS.
  Map<ShortcutActivator, Intent> _buildShortcuts() {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator command(LogicalKeyboardKey key) =>
        SingleActivator(key, control: !isMac, meta: isMac);
    return {
      command(LogicalKeyboardKey.keyK): VoidCallbackIntent(
        () => unawaited(_openQuickSwitcher()),
      ),
      // Held down, Esc must not run through the reply and on to the next step.
      const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
          VoidCallbackIntent(() => _pane?.handleEscape()),
    };
  }

  Future<void> _openQuickSwitcher() async {
    if (_switcherOpen) return;
    _switcherOpen = true;
    final selected = await showQuickSwitcher(context, widget.workspace);
    _switcherOpen = false;
    if (!mounted || selected == null) return;
    widget.onOpenDestination(selected);
    // A new channel focuses its own box. The open channel has nothing to
    // announce, and the dialog took the focus from it.
    _pane?.focusComposer();
  }

  /// Sends a printable key to the composer, unless the focus is in a text field
  /// that wants it. Space stays out: on a focused button it means press.
  KeyEventResult _routeTyping(FocusNode _, KeyEvent event) {
    final character = event.character;
    if (event is! KeyDownEvent ||
        character == null ||
        !_isPrintable(character) ||
        _holdsCommandModifier ||
        _focusIsInTextField) {
      return KeyEventResult.ignored;
    }
    return (_pane?.typeInComposer(character) ?? false)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  static bool _isPrintable(String character) =>
      character.trim().isNotEmpty &&
      !character.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

  static bool get _holdsCommandModifier {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed;
  }

  static bool get _focusIsInTextField =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  @override
  Widget build(BuildContext context) => _ShellKeyboardScope(
    paneKey: _paneKey,
    child: Shortcuts(
      shortcuts: _shortcuts,
      // A scope, so a widget that gives up the focus leaves it here. Above this
      // line no key would reach the map or the composer.
      child: FocusScope(
        debugLabel: 'Shell keyboard',
        autofocus: true,
        onKeyEvent: _routeTyping,
        child: widget.child,
      ),
    ),
  );
}

class _ShellKeyboardScope extends InheritedWidget {
  const _ShellKeyboardScope({required this.paneKey, required super.child});

  final GlobalKey<ConversationPaneState> paneKey;

  @override
  bool updateShouldNotify(_ShellKeyboardScope oldWidget) => false;
}
