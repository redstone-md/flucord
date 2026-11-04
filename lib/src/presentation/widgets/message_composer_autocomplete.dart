part of 'message_composer.dart';

mixin _ComposerAutocompleteStateMixin on State<MessageComposer> {
  final OverlayPortalController _autocompleteOverlayController =
      OverlayPortalController();
  final LayerLink _autocompleteLayerLink = LayerLink();
  final ScrollController _autocompleteScroll = ScrollController();
  List<ComposerAutocompleteSuggestion> _autocompleteSuggestions = const [];
  int _autocompleteSelection = 0;

  /// The query being typed, also while nothing loaded matches it. Null once
  /// the user closed the list, so nothing opens it again until they type.
  ComposerAutocompleteQuery? _autocompleteQuery;

  /// The catalog queries read. It moves only to a catalog with different data,
  /// so the suggestions it built survive a rebuild of the pane.
  late ComposerAutocompleteCatalog _autocompleteCatalog =
      widget.autocompleteCatalog;

  /// The last text asked about in this channel. Updates that arrive while the
  /// query stays the same must not ask again: each one is a gateway frame, and
  /// the gateway limits them.
  String? _requestedMemberQuery;

  TextEditingController get _autocompleteTextController;
  FocusNode get _autocompleteFocusNode;

  /// Answers the keys pressed in the box. It offers each key to
  /// [_handleComposerAutocompleteKey] first.
  FocusOnKeyEventCallback get _composerKeyHandler;

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
    _autocompleteScroll.dispose();
  }

  void _handleAutocompleteFocus() {
    if (!_autocompleteFocusNode.hasFocus) _dismissComposerAutocomplete();
  }

  /// Takes the catalog of a rebuilt pane. A closed list stays closed, and the
  /// new catalog builds nothing until a query needs it.
  void _updateAutocompleteCatalog({required bool channelChanged}) {
    if (channelChanged) _requestedMemberQuery = null;
    if (_autocompleteCatalog == widget.autocompleteCatalog) return;
    _autocompleteCatalog = widget.autocompleteCatalog;
    if (channelChanged || _autocompleteQuery == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshComposerAutocomplete();
    });
  }

  /// A large guild sends only a fraction of its members at login, so the names
  /// already loaded are not the names that can be mentioned. The answer arrives
  /// as ordinary member updates, which is what refreshes the list.
  void _requestMembersFor(ComposerAutocompleteQuery query) {
    if (query.trigger != ComposerAutocompleteTrigger.mention ||
        query.text == _requestedMemberQuery) {
      return;
    }
    _requestedMemberQuery = query.text;
    widget.onSearchMembers?.call(query.text);
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
    _requestMembersFor(query);
    final suggestions = _autocompleteCatalog.suggestionsFor(query);
    if (suggestions.isEmpty) {
      _dismissComposerAutocomplete();
      _autocompleteQuery = query;
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
    _revealAutocompleteSelection();
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

  /// Runs [change] and leaves the list closed. Text put in the box from code,
  /// such as a draft coming back, is not the user asking for suggestions.
  void _withAutocompleteClosed(VoidCallback change) {
    _autocompleteTextController.removeListener(_refreshComposerAutocomplete);
    change();
    _autocompleteTextController.addListener(_refreshComposerAutocomplete);
    _autocompleteSuggestions = const [];
    // This runs during a build, where the portal cannot be hidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _autocompleteSuggestions.isEmpty) {
        _resetComposerAutocomplete();
      }
    });
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
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
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
    _revealAutocompleteSelection();
  }

  /// Scrolls the list just far enough to show the selected row. Called only
  /// when the selection moves by key or by a new query: a row under the mouse
  /// is on screen already, and the list must not move under the pointer.
  void _revealAutocompleteSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_autocompleteScroll.hasClients) return;
      final position = _autocompleteScroll.position;
      final top = _autocompleteSelection * _ComposerAutocompleteMenu.rowHeight;
      final bottom = top + _ComposerAutocompleteMenu.rowHeight;
      if (top < position.pixels) {
        position.jumpTo(top);
      } else if (bottom > position.pixels + position.viewportDimension) {
        position.jumpTo(bottom - position.viewportDimension);
      }
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
                    scrollController: _autocompleteScroll,
                    onHover: _hoverComposerAutocomplete,
                    onSelected: _selectComposerAutocomplete,
                  ),
                ),
              ),
            ],
          ),
          child: CompositedTransformTarget(
            link: _autocompleteLayerLink,
            child: Focus(onKeyEvent: _composerKeyHandler, child: child),
          ),
        ),
      );
}

class _ComposerAutocompleteMenu extends StatelessWidget {
  const _ComposerAutocompleteMenu({
    required this.suggestions,
    required this.selectedIndex,
    required this.trigger,
    required this.scrollController,
    required this.onHover,
    required this.onSelected,
  });

  static const rowHeight = 44.0;

  final List<ComposerAutocompleteSuggestion> suggestions;
  final int selectedIndex;
  final ComposerAutocompleteTrigger? trigger;
  final ScrollController scrollController;
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
        borderRadius: FlucordRadius.small,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 32.0 + visibleCount * rowHeight,
        child: Column(
          children: [
            SizedBox(
              height: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    switch (trigger) {
                      ComposerAutocompleteTrigger.channel => 'CHANNELS',
                      ComposerAutocompleteTrigger.emoji => 'EMOJI',
                      _ => 'MEMBERS AND ROLES',
                    },
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: FlucordType.caption,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: EdgeInsets.zero,
                itemCount: suggestions.length,
                itemExtent: rowHeight,
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
    final isEmoji = suggestion.kind == ComposerAutocompleteKind.emoji;
    final prefix = isEmoji
        ? ''
        : suggestion.kind == ComposerAutocompleteKind.channel
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
                  color: selected ? context.surfaces.brand : Colors.transparent,
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
                          isEmoji
                              ? ':${suggestion.label}:'
                              : '$prefix${suggestion.label}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: FlucordType.caption,
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
                            fontSize: FlucordType.caption,
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
    if (suggestion.kind == ComposerAutocompleteKind.emoji) {
      if (suggestion.unicodeGlyph case final String glyph) {
        return SizedBox.square(
          dimension: 28,
          child: Center(
            child: Text(
              glyph,
              style: const TextStyle(fontSize: FlucordType.title),
            ),
          ),
        );
      }
      return SizedBox.square(
        dimension: 28,
        child: ClipRRect(
          borderRadius: FlucordRadius.small,
          child: RemoteIdentityImage(
            url: suggestion.emojiUrl,
            fallback: Container(
              color: color.withValues(alpha: 0.16),
              alignment: Alignment.center,
              child: Text(
                suggestion.label.substring(0, 1).toUpperCase(),
                style: TextStyle(fontSize: FlucordType.caption, color: color),
              ),
            ),
          ),
        ),
      );
    }
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
                    fontSize: FlucordType.caption,
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
        borderRadius: FlucordRadius.small,
      ),
      child: FlucordIcon(
        suggestion.kind == ComposerAutocompleteKind.role
            ? FlucordIcons.mention
            : FlucordIcons.textChannel,
        size: 16,
        color: color,
      ),
    );
  }
}
