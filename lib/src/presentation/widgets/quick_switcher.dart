import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/quick_switcher_catalog.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'count_badge.dart';
import 'flucord_dialog.dart';

part 'quick_switcher_destination_row.dart';

/// Asks where to go, and answers with the destination, or null when the user
/// backs out. Backing out gives the focus back to where it was.
Future<QuickSwitcherDestination?> showQuickSwitcher(
  BuildContext context,
  ChatWorkspace workspace,
) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final selected = await showDialog<QuickSwitcherDestination>(
    context: context,
    builder: (context) => _QuickSwitcherDialog(
      catalog: QuickSwitcherCatalog.fromWorkspace(workspace),
    ),
  );
  if (selected == null && (previousFocus?.canRequestFocus ?? false)) {
    previousFocus!.requestFocus();
  }
  return selected;
}

class _QuickSwitcherDialog extends StatefulWidget {
  const _QuickSwitcherDialog({required this.catalog});

  final QuickSwitcherCatalog catalog;

  @override
  State<_QuickSwitcherDialog> createState() => _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends State<_QuickSwitcherDialog> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _rowKeys = {};
  late List<QuickSwitcherDestination> _results;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _results = widget.catalog.destinations;
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height - 96;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Quick Switcher',
      explicitChildNodes: true,
      child: FlucordDialog.frame(
        key: const ValueKey('quick-switcher'),
        alignment: const Alignment(0, -0.48),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: SizedBox(
          width: 640,
          height: math.min(520, availableHeight),
          child: Focus(
            onKeyEvent: _handleKeyEvent,
            child: Column(
              children: [
                _SearchField(
                  controller: _queryController,
                  resultCount: _results.length,
                  onChanged: _search,
                ),
                Divider(height: 1, color: context.surfaces.border),
                Expanded(child: _buildResults(context)),
                Divider(height: 1, color: context.surfaces.border),
                const _QuickSwitcherFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlucordIcon(
              FlucordIcons.noResults,
              size: 28,
              color: context.surfaces.muted,
            ),
            const SizedBox(height: 8),
            const Text('No destinations found'),
            const SizedBox(height: 2),
            Text(
              'Try a server, channel, thread, or person',
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
              ),
            ),
          ],
        ),
      );
    }

    final children = <Widget>[];
    QuickSwitcherDestinationKind? previousKind;
    for (var index = 0; index < _results.length; index++) {
      final destination = _results[index];
      if (destination.kind != previousKind) {
        children.add(_GroupLabel(kind: destination.kind));
        previousKind = destination.kind;
      }
      children.add(
        _DestinationRow(
          key: _rowKeys.putIfAbsent(destination.key, GlobalKey.new),
          destination: destination,
          selected: index == _selectedIndex,
          onHover: () => _select(index, reveal: false),
          onPressed: () => Navigator.of(context).pop(destination),
        ),
      );
    }
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: _results.length > 8,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        children: children,
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submitSelection();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _search(String query) {
    setState(() {
      _results = widget.catalog.search(query);
      _selectedIndex = 0;
      _rowKeys.removeWhere(
        (key, _) => !_results.any((destination) => destination.key == key),
      );
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    final next = (_selectedIndex + delta) % _results.length;
    _select(next, reveal: true);
  }

  void _select(int index, {required bool reveal}) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    if (!reveal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _rowKeys[_results[_selectedIndex].key]?.currentContext;
      if (rowContext == null) return;
      Scrollable.ensureVisible(
        rowContext,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  void _submitSelection() {
    if (_results.isEmpty) return;
    Navigator.of(context).pop(_results[_selectedIndex]);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.resultCount,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int resultCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: TextField(
      key: const ValueKey('quick-switcher-search'),
      controller: controller,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: FlucordType.body,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Where would you like to go?',
        semanticCounterText: '$resultCount destinations',
        prefixIcon: const FlucordIcon(FlucordIcons.search, size: 20),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Center(
            widthFactor: 1,
            child: Text(
              '$resultCount',
              key: const ValueKey('quick-switcher-result-count'),
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
              ),
            ),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FlucordRadius.medium,
          borderSide: BorderSide(color: context.surfaces.focusRing, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.kind});

  final QuickSwitcherDestinationKind kind;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 8, 5),
    child: Text(
      _groupName(kind).toUpperCase(),
      style: FlucordTextRole.caption.strong.copyWith(
        color: context.surfaces.muted,
        letterSpacing: 0.55,
      ),
    ),
  );
}
