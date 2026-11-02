import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/quick_switcher_catalog.dart';
import '../domain/chat_models.dart';
import 'conversation_pane.dart';
import 'widgets/quick_switcher.dart';

/// A move through the channels and the servers. The shell knows their order.
enum ShellStep {
  previousChannel,
  nextChannel,
  previousUnreadChannel,
  nextUnreadChannel,
  previousMentionChannel,
  nextMentionChannel,
  previousServer,
  nextServer,
}

extension ShellKeyboardWidget on Widget {
  Widget withShellKeyboard({
    required ChatWorkspace workspace,
    required String? channelId,
    required ValueChanged<QuickSwitcherDestination> onOpenDestination,
    required ValueChanged<ShellStep> onStep,
    required ValueChanged<String> onOpenChannel,
  }) => ShellKeyboard(
    workspace: workspace,
    channelId: channelId,
    onOpenDestination: onOpenDestination,
    onStep: onStep,
    onOpenChannel: onOpenChannel,
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
    required this.channelId,
    required this.onOpenDestination,
    required this.onStep,
    required this.onOpenChannel,
    required this.child,
    super.key,
  });

  final ChatWorkspace workspace;

  /// The channel on screen, which is what the back and forward keys remember.
  final String? channelId;
  final ValueChanged<QuickSwitcherDestination> onOpenDestination;
  final ValueChanged<ShellStep> onStep;

  /// Opens a channel the back or forward key went to.
  final ValueChanged<String> onOpenChannel;
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
  final _ChannelHistory _history = _ChannelHistory();
  bool _switcherOpen = false;

  ConversationPaneState? get _pane => _paneKey.currentState;

  @override
  void initState() {
    super.initState();
    _history.visit(widget.channelId);
  }

  @override
  void didUpdateWidget(covariant ShellKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _history.visit(widget.channelId);
  }

  /// The same table as Discord's: Ctrl on Windows and Linux is Cmd on macOS,
  /// and Alt is Option. Back and forward use Cmd and the brackets on macOS,
  /// because there Option and the side arrows move the caret by a word.
  Map<ShortcutActivator, Intent> _buildShortcuts() {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator command(
      LogicalKeyboardKey key, {
      bool alt = false,
      bool shift = false,
    }) => SingleActivator(
      key,
      control: !isMac,
      meta: isMac,
      alt: alt,
      shift: shift,
    );
    Intent step(ShellStep step) =>
        VoidCallbackIntent(() => widget.onStep(step));
    Intent page(int direction) =>
        VoidCallbackIntent(() => _pane?.scrollTimelinePage(direction));
    final back = VoidCallbackIntent(() => _openFromHistory(_history.back()));
    final forward = VoidCallbackIntent(
      () => _openFromHistory(_history.forward()),
    );
    const up = LogicalKeyboardKey.arrowUp;
    const down = LogicalKeyboardKey.arrowDown;
    return {
      const SingleActivator(up, alt: true): step(ShellStep.previousChannel),
      const SingleActivator(down, alt: true): step(ShellStep.nextChannel),
      const SingleActivator(up, alt: true, shift: true): step(
        ShellStep.previousUnreadChannel,
      ),
      const SingleActivator(down, alt: true, shift: true): step(
        ShellStep.nextUnreadChannel,
      ),
      command(up, alt: true, shift: true): step(
        ShellStep.previousMentionChannel,
      ),
      command(down, alt: true, shift: true): step(ShellStep.nextMentionChannel),
      command(up, alt: true): step(ShellStep.previousServer),
      command(down, alt: true): step(ShellStep.nextServer),
      if (isMac) ...{
        command(LogicalKeyboardKey.bracketLeft): back,
        command(LogicalKeyboardKey.bracketRight): forward,
      } else ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            forward,
      },
      const SingleActivator(LogicalKeyboardKey.pageUp): page(-1),
      const SingleActivator(LogicalKeyboardKey.pageDown): page(1),
      command(LogicalKeyboardKey.keyK): VoidCallbackIntent(
        () => unawaited(_openQuickSwitcher()),
      ),
      // Held down, Esc must not run through the reply and on to the next step.
      const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
          VoidCallbackIntent(() => _pane?.handleEscape()),
    };
  }

  void _openFromHistory(String? channelId) {
    if (channelId != null) widget.onOpenChannel(channelId);
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

/// The channels the reader has been to, for the back and forward keys.
final class _ChannelHistory {
  static const _limit = 50;

  final List<String> _visited = [];
  int _cursor = -1;

  /// Notes the channel on screen. Going back to a channel lands here too, and
  /// changes nothing, because the cursor already points at it.
  void visit(String? channelId) {
    if (channelId == null) return;
    if (_cursor >= 0 && _visited[_cursor] == channelId) return;
    _visited
      ..removeRange(_cursor + 1, _visited.length)
      ..add(channelId);
    if (_visited.length > _limit) _visited.removeAt(0);
    _cursor = _visited.length - 1;
  }

  String? back() => _cursor > 0 ? _visited[--_cursor] : null;

  String? forward() =>
      _cursor < _visited.length - 1 ? _visited[++_cursor] : null;
}

class _ShellKeyboardScope extends InheritedWidget {
  const _ShellKeyboardScope({required this.paneKey, required super.child});

  final GlobalKey<ConversationPaneState> paneKey;

  @override
  bool updateShouldNotify(_ShellKeyboardScope oldWidget) => false;
}
