import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'message_sticker_view.dart';

typedef SendStickersCallback = Future<bool> Function(List<String> stickerIds);

class StickerPickerButton extends StatefulWidget {
  const StickerPickerButton({
    required this.stickers,
    required this.isSending,
    required this.onSend,
    this.assetBuilder = buildStickerAsset,
    super.key,
  });

  final List<GuildSticker> stickers;
  final bool isSending;
  final SendStickersCallback onSend;
  final StickerAssetBuilder assetBuilder;

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
        child: _StickerPickerPanel(
          stickers: widget.stickers,
          queryController: _queryController,
          selectedIds: _selectedIds,
          isSending: widget.isSending || _isSubmitting,
          sendFailed: _sendFailed,
          assetBuilder: widget.assetBuilder,
          onQueryChanged: (_) => setState(() {}),
          onToggle: _toggleSticker,
          onSend: _send,
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
        .toList(growable: false);
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
                      child: InkWell(
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
