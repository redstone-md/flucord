import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/expression_favorites_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'expression_favorite_star.dart';
import 'message_sticker_view.dart';

typedef SendStickersCallback = Future<bool> Function(List<String> stickerIds);

class StickerPickerButton extends StatefulWidget {
  const StickerPickerButton({
    required this.stickers,
    required this.isSending,
    required this.onSend,
    this.assetBuilder = buildStickerAsset,
    this.favorites,
    super.key,
  });

  final List<GuildSticker> stickers;
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

  @override
  void didUpdateWidget(covariant StickerPickerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final availableIds = widget.stickers.map((sticker) => sticker.id).toSet();
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
            stickers: widget.stickers,
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
      onPressed: widget.isSending || widget.stickers.isEmpty
          ? null
          : _toggleMenu,
      icon: const Icon(Icons.emoji_emotions_outlined, size: 19),
      tooltip: 'Stickers',
    ),
  );
}

class _StickerPickerPanel extends StatelessWidget {
  const _StickerPickerPanel({
    required this.stickers,
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

  final List<GuildSticker> stickers;
  final TextEditingController queryController;
  final Set<String> selectedIds;
  final bool isSending;
  final bool sendFailed;
  final StickerAssetBuilder assetBuilder;
  final ExpressionFavoritesController? favorites;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onToggle;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final query = queryController.text.trim().toLowerCase();
    final visible = stickers
        .where((sticker) {
          if (query.isEmpty) return true;
          return sticker.name.toLowerCase().contains(query) ||
              sticker.tags.any((tag) => tag.toLowerCase().contains(query));
        })
        .toList();
    final starred = favorites;
    if (starred != null && query.isEmpty) {
      // Starred first while browsing, but not while searching: a search is a
      // question about names, and reordering its answers hides the match.
      final frecency = starred.favorites.stickerFrecency;
      visible.sort((a, b) {
        final left = starred.isFavoriteSticker(a.id) ? 0 : 1;
        final right = starred.isFavoriteSticker(b.id) ? 0 : 1;
        if (left != right) return left.compareTo(right);
        // Within each half, what the account actually reaches for. The table
        // is the server's count, so this matches the order Discord's own
        // client shows.
        return (frecency.scoreFor(b.id)?.score ?? 0).compareTo(
          frecency.scoreFor(a.id)?.score ?? 0,
        );
      });
    }
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
              : GridView.builder(
                  primary: false,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final sticker = visible[index];
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
                                  color: selected
                                      ? FlucordColors.brand
                                      : Colors.transparent,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: assetBuilder(context, sticker.item),
                            ),
                          ),
                          if (favorites case final ExpressionFavoritesController
                              controller)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: ExpressionFavoriteStar(
                                key: ValueKey('sticker-star-${sticker.id}'),
                                controller: controller,
                                isFavorite: controller.isFavoriteSticker(
                                  sticker.id,
                                ),
                                onPressed: () =>
                                    controller.toggleSticker(sticker.id),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
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
}
