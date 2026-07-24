part of 'message_composer.dart';

mixin _ComposerAutocompleteStateMixin on State<MessageComposer> {
  final OverlayPortalController _autocompleteOverlayController =
      OverlayPortalController();
  final LayerLink _autocompleteLayerLink = LayerLink();
  List<ComposerAutocompleteSuggestion> _autocompleteSuggestions = const [];
  ComposerAutocompleteQuery? _autocompleteQuery;
  int _autocompleteSelection = 0;

  TextEditingController get _autocompleteTextController;
  FocusNode get _autocompleteFocusNode;

  void _initializeComposerAutocomplete() {
    _autocompleteTextController.addListener(_refreshComposerAutocomplete);
    _autocompleteFocusNode.addListener(_handleAutocompleteFocus);
  }

  void _disposeComposerAutocomplete() {
    _autocompleteTextController.removeListener(_refreshComposerAutocomplete);
    _autocompleteFocusNode.removeListener(_handleAutocompleteFocus);
    if (_autocompleteOverlayController.isShowing) {
      _autocompleteOverlayController.hide();
    }
  }

  void _handleAutocompleteFocus() {
    if (!_autocompleteFocusNode.hasFocus) _dismissComposerAutocomplete();
  }

  void _refreshComposerAutocomplete() {
    if (!mounted || !_autocompleteFocusNode.hasFocus) {
      _dismissComposerAutocomplete();
      return;
    }
    final value = _autocompleteTextController.value;
    if (!value.selection.isValid ||
        !value.selection.isCollapsed ||
        (value.composing.isValid && !value.composing.isCollapsed)) {
      _dismissComposerAutocomplete();
      return;
    }
    final query = ComposerAutocompleteQuery.parse(
      value.text,
      value.selection.extentOffset,
    );
    if (query == null) {
      _dismissComposerAutocomplete();
      return;
    }
    final suggestions = widget.autocompleteCatalog.suggestionsFor(query);
    if (suggestions.isEmpty) {
      _dismissComposerAutocomplete();
      return;
    }
    final selectedId = _autocompleteSuggestions.isEmpty
        ? null
        : _autocompleteSuggestions[_autocompleteSelection.clamp(
                0,
                _autocompleteSuggestions.length - 1,
              )]
              .id;
    final retainedIndex = selectedId == null
        ? -1
        : suggestions.indexWhere((suggestion) => suggestion.id == selectedId);
    setState(() {
      _autocompleteQuery = query;
      _autocompleteSuggestions = suggestions;
      _autocompleteSelection = retainedIndex < 0 ? 0 : retainedIndex;
    });
    if (!_autocompleteOverlayController.isShowing) {
      _autocompleteOverlayController.show();
    }
  }

  void _resetComposerAutocomplete() {
    if (_autocompleteOverlayController.isShowing) {
      _autocompleteOverlayController.hide();
    }
    _autocompleteSuggestions = const [];
    _autocompleteQuery = null;
    _autocompleteSelection = 0;
  }

  void _dismissComposerAutocomplete() {
    final hadSuggestions = _autocompleteSuggestions.isNotEmpty;
    _resetComposerAutocomplete();
    if (mounted && hadSuggestions) setState(() {});
  }

  KeyEventResult _handleComposerAutocompleteKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || _autocompleteSuggestions.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveComposerAutocompleteSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveComposerAutocompleteSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _selectComposerAutocomplete(_autocompleteSelection);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismissComposerAutocomplete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveComposerAutocompleteSelection(int delta) {
    if (_autocompleteSuggestions.isEmpty) return;
    setState(() {
      _autocompleteSelection =
          (_autocompleteSelection + delta) % _autocompleteSuggestions.length;
    });
  }

  void _selectComposerAutocomplete(int index) {
    final query = _autocompleteQuery;
    if (query == null ||
        index < 0 ||
        index >= _autocompleteSuggestions.length) {
      return;
    }
    final edit = _autocompleteSuggestions[index].apply(
      _autocompleteTextController.text,
      query,
    );
    _resetComposerAutocomplete();
    _autocompleteTextController.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.cursor),
    );
    _autocompleteFocusNode.requestFocus();
  }

  void _hoverComposerAutocomplete(int index) {
    if (index == _autocompleteSelection) return;
    setState(() => _autocompleteSelection = index);
  }

  Widget _buildComposerAutocompletePortal({required Widget child}) =>
      LayoutBuilder(
        builder: (context, constraints) => OverlayPortal(
          controller: _autocompleteOverlayController,
          overlayChildBuilder: (context) => Stack(
            children: [
              CompositedTransformFollower(
                link: _autocompleteLayerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topLeft,
                followerAnchor: Alignment.bottomLeft,
                offset: const Offset(0, -4),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: _ComposerAutocompleteMenu(
                    suggestions: _autocompleteSuggestions,
                    selectedIndex: _autocompleteSelection,
                    trigger: _autocompleteQuery?.trigger,
                    onHover: _hoverComposerAutocomplete,
                    onSelected: _selectComposerAutocomplete,
                  ),
                ),
              ),
            ],
          ),
          child: CompositedTransformTarget(
            link: _autocompleteLayerLink,
            child: Focus(
              onKeyEvent: _handleComposerAutocompleteKey,
              child: child,
            ),
          ),
        ),
      );
}

class _ComposerAutocompleteMenu extends StatelessWidget {
  const _ComposerAutocompleteMenu({
    required this.suggestions,
    required this.selectedIndex,
    required this.trigger,
    required this.onHover,
    required this.onSelected,
  });

  final List<ComposerAutocompleteSuggestion> suggestions;
  final int selectedIndex;
  final ComposerAutocompleteTrigger? trigger;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final visibleCount = suggestions.length.clamp(1, 6);
    return Material(
      key: const ValueKey('composer-autocomplete'),
      color: context.surfaces.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 32.0 + visibleCount * 44.0,
        child: Column(
          children: [
            SizedBox(
              height: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    trigger == ComposerAutocompleteTrigger.channel
                        ? 'CHANNELS'
                        : 'MEMBERS AND ROLES',
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: suggestions.length,
                itemExtent: 44,
                itemBuilder: (context, index) => _ComposerAutocompleteRow(
                  suggestion: suggestions[index],
                  selected: index == selectedIndex,
                  onHover: () => onHover(index),
                  onSelected: () => onSelected(index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerAutocompleteRow extends StatelessWidget {
  const _ComposerAutocompleteRow({
    required this.suggestion,
    required this.selected,
    required this.onHover,
    required this.onSelected,
  });

  final ComposerAutocompleteSuggestion suggestion;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final prefix = suggestion.kind == ComposerAutocompleteKind.channel
        ? '#'
        : '@';
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$prefix${suggestion.label}, ${suggestion.description}',
        child: InkWell(
          key: ValueKey(
            'composer-suggestion-${suggestion.kind.name}-${suggestion.id}',
          ),
          onTap: onSelected,
          child: Container(
            decoration: BoxDecoration(
              color: selected ? context.surfaces.raised : Colors.transparent,
              border: Border(
                left: BorderSide(
                  width: 2,
                  color: selected ? FlucordColors.brand : Colors.transparent,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _ComposerAutocompleteGlyph(suggestion: suggestion),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$prefix${suggestion.label}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          suggestion.description,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.surfaces.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
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

class _ComposerAutocompleteGlyph extends StatelessWidget {
  const _ComposerAutocompleteGlyph({required this.suggestion});

  final ComposerAutocompleteSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final color = Color(
      suggestion.colorValue ?? context.surfaces.muted.toARGB32(),
    );
    if (suggestion.kind == ComposerAutocompleteKind.member) {
      return SizedBox.square(
        dimension: 28,
        child: ClipOval(
          child: RemoteIdentityImage(
            url: suggestion.avatarUrl,
            fallback: ColoredBox(
              color: color,
              child: Center(
                child: Text(
                  suggestion.initials ?? '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        suggestion.kind == ComposerAutocompleteKind.role
            ? Icons.alternate_email_rounded
            : Icons.tag_rounded,
        size: 16,
        color: color,
      ),
    );
  }
}
