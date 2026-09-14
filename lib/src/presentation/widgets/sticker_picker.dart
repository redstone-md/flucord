import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/expression_favorites_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'expression_favorite_star.dart';
import 'message_sticker_view.dart';

typedef SendStickersCallback = Future<bool> Function(List<String> stickerIds);

/// The stickers of one server, listed under the server's own name.
final class StickerServerSection {
  const StickerServerSection({required this.spaceName, required this.stickers});

  final String spaceName;
  final List<GuildSticker> stickers;
}

/// The servers' stickers grouped for the picker, the space the composer sits
/// in first.
List<StickerServerSection> stickerSectionsFromWorkspace(
  ChatWorkspace workspace,
  String currentSpaceId,
) {
  final sections = <StickerServerSection>[];
  for (final space in [
    ...workspace.spaces.where((space) => space.id == currentSpaceId),
    ...workspace.spaces.where((space) => space.id != currentSpaceId),
  ]) {
    final stickers = workspace.stickersFor(space.id);
    if (stickers.isNotEmpty) {
      sections.add(
        StickerServerSection(spaceName: space.name, stickers: stickers),
      );
    }
  }
  return sections;
}

class StickerPickerButton extends StatefulWidget {
  const StickerPickerButton({
    required this.sections,
    required this.isSending,
    required this.onSend,
    this.assetBuilder = buildStickerAsset,
    this.favorites,
    super.key,
  });

  final List<StickerServerSection> sections;
  final bool isSending;
  final SendStickersCallback onSend;
  final StickerAssetBuilder assetBuilder;

  /// The favourites store, when the transport has one.
  final ExpressionFavoritesController? favorites;

  @override
  State<StickerPickerButton> createState() => _StickerPickerButtonState();
}

class _StickerPickerButtonState extends State<StickerPickerButton> {
  final MenuController _menuController = MenuController();
  final TextEditingController _queryController = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _isSubmitting = false;
  bool _sendFailed = false;

  List<GuildSticker> get _allStickers => [
    for (final section in widget.sections) ...section.stickers,
  ];

  @override
  void didUpdateWidget(covariant StickerPickerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final availableIds = _allStickers.map((sticker) => sticker.id).toSet();
    _selectedIds.removeWhere((id) => !availableIds.contains(id));
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
      // Read on opening rather than on build: the blob costs a request, and a
      // composer that never opens the picker should not spend one.
      unawaited(widget.favorites?.load());
    }
  }

  void _toggleSticker(String id) {
    setState(() {
      _sendFailed = false;
      if (!_selectedIds.remove(id) && _selectedIds.length < 3) {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _send() async {
    if (_selectedIds.isEmpty || widget.isSending || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _sendFailed = false;
    });
    final sent = await widget.onSend(_selectedIds.toList(growable: false));
    if (!mounted) return;
    if (sent) {
      setState(() {
        _selectedIds.clear();
        _isSubmitting = false;
        _sendFailed = false;
      });
      _menuController.close();
    } else {
      setState(() {
        _isSubmitting = false;
        _sendFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menuController,
    useRootOverlay: true,
    consumeOutsideTap: false,
    crossAxisUnconstrained: false,
    style: MenuStyle(
      fixedSize: const WidgetStatePropertyAll(Size(336, 380)),
      backgroundColor: WidgetStatePropertyAll(context.surfaces.surface),
      side: WidgetStatePropertyAll(BorderSide(color: context.surfaces.border)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    ),
    onClose: () {
      _queryController.clear();
      if (mounted) setState(() {});
    },
    menuChildren: [
      SizedBox(
        key: const ValueKey('sticker-picker'),
        width: 336,
        height: 380,
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.favorites]),
          builder: (context, _) => _StickerPickerPanel(
            sections: widget.sections,
            queryController: _queryController,
            selectedIds: _selectedIds,
            isSending: widget.isSending || _isSubmitting,
            sendFailed: _sendFailed,
            assetBuilder: widget.assetBuilder,
            favorites: widget.favorites,
            onQueryChanged: (_) => setState(() {}),
            onToggle: _toggleSticker,
            onSend: _send,
          ),
        ),
      ),
    ],
    builder: (context, controller, child) => IconButton(
      key: const ValueKey('open-sticker-picker'),
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: EdgeInsets.zero,
      onPressed: widget.isSending || _allStickers.isEmpty ? null : _toggleMenu,
      icon: const Icon(Icons.emoji_emotions_outlined, size: 19),
      tooltip: 'Stickers',
    ),
  );
}

class _StickerPickerPanel extends StatelessWidget {
  const _StickerPickerPanel({
    required this.sections,
    required this.queryController,
    required this.selectedIds,
    required this.isSending,
    required this.sendFailed,
    required this.assetBuilder,
    required this.favorites,
    required this.onQueryChanged,
    required this.onToggle,
    required this.onSend,
  });

  final List<StickerServerSection> sections;
  final TextEditingController queryController;
  final Set<String> selectedIds;
  final bool isSending;
  final bool sendFailed;
  final StickerAssetBuilder assetBuilder;
  final ExpressionFavoritesController? favorites;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onToggle;
  final VoidCallback onSend;

  bool _matches(GuildSticker sticker, String query) {
    if (query.isEmpty) return true;
    return sticker.name.toLowerCase().contains(query) ||
        sticker.tags.any((tag) => tag.toLowerCase().contains(query));
  }

  List<(String, List<GuildSticker>)> _visibleSections(String query) {
    return [
      for (final section in sections)
        if (section.stickers.any((sticker) => _matches(sticker, query)))
          (
            section.spaceName,
            section.stickers
                .where((sticker) => _matches(sticker, query))
                .toList(growable: false),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final query = queryController.text.trim().toLowerCase();
    final starred = favorites;
    final visible = starred != null && query.isEmpty
        ? _rankedSections(starred)
        : _visibleSections(query);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            key: const ValueKey('sticker-search'),
            controller: queryController,
            autofocus: true,
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              hintText: 'Search stickers',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
        ),
        Divider(height: 1, color: context.surfaces.border),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    'No stickers found',
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 11,
                    ),
                  ),
                )
              : CustomScrollView(
                  key: const ValueKey('sticker-grid-scroll'),
                  primary: false,
                  slivers: [
                    for (final (spaceName, stickers) in visible) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            spaceName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.surfaces.muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        sliver: SliverGrid.builder(
                          itemCount: stickers.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                              ),
                          itemBuilder: (context, index) =>
                              _stickerTile(context, stickers[index]),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        Divider(height: 1, color: context.surfaces.border),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  sendFailed
                      ? 'Could not send stickers.'
                      : '${selectedIds.length}/3 selected',
                  style: TextStyle(
                    color: sendFailed
                        ? Theme.of(context).colorScheme.error
                        : context.surfaces.muted,
                    fontSize: 10,
                  ),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('send-stickers'),
                onPressed: selectedIds.isEmpty || isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 15),
                label: const Text('Send'),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ],
    );
  }

  /// Sections while browsing: starred first within each server, then what
  /// the account actually reaches for. A search keeps the servers' own order,
  /// because a search is a question about names and reordering its answers
  /// hides the match.
  List<(String, List<GuildSticker>)> _rankedSections(
    ExpressionFavoritesController starred,
  ) {
    final frecency = starred.favorites.stickerFrecency;
    return [
      for (final (spaceName, stickers) in _visibleSections(''))
        (
          spaceName,
          [...stickers]..sort((left, right) {
            final leftStarred = starred.isFavoriteSticker(left.id) ? 0 : 1;
            final rightStarred = starred.isFavoriteSticker(right.id) ? 0 : 1;
            if (leftStarred != rightStarred) {
              return leftStarred.compareTo(rightStarred);
            }
            return (frecency.scoreFor(right.id)?.score ?? 0).compareTo(
              frecency.scoreFor(left.id)?.score ?? 0,
            );
          }),
        ),
    ];
  }

  Widget _stickerTile(BuildContext context, GuildSticker sticker) {
    final selected = selectedIds.contains(sticker.id);
    return Semantics(
      label: sticker.name,
      button: true,
      selected: selected,
      onTap: () => onToggle(sticker.id),
      excludeSemantics: true,
      child: Stack(
        children: [
          InkWell(
            key: ValueKey('sticker-option-${sticker.id}'),
            onTap: () => onToggle(sticker.id),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: selected
                    ? FlucordColors.brand.withValues(alpha: 0.14)
                    : Colors.transparent,
                border: Border.all(
                  color: selected ? FlucordColors.brand : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: assetBuilder(context, sticker.item),
            ),
          ),
          if (favorites case final ExpressionFavoritesController controller)
            Positioned(
              top: 0,
              right: 0,
              child: ExpressionFavoriteStar(
                key: ValueKey('sticker-star-${sticker.id}'),
                controller: controller,
                isFavorite: controller.isFavoriteSticker(sticker.id),
                onPressed: () => controller.toggleSticker(sticker.id),
              ),
            ),
        ],
      ),
    );
  }
}
