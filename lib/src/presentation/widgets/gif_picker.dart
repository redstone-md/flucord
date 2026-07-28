import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/gif_picker_controller.dart';
import '../../domain/gif_picker.dart';
import '../../theme/flucord_theme.dart';

/// The composer's GIF button, and the sheet it opens.
class GifPickerButton extends StatelessWidget {
  const GifPickerButton({
    required this.controller,
    required this.onSelected,
    super.key,
  });

  final GifPickerController controller;

  /// Called with the url a message should carry.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('gif-picker-open'),
      tooltip: 'GIF',
      onPressed: () => unawaited(
        GifPickerSheet.show(
          context,
          controller: controller,
          onSelected: onSelected,
        ),
      ),
      icon: const Icon(Icons.gif_box_outlined),
    );
  }
}

/// Search box, categories and the result grid.
class GifPickerSheet extends StatefulWidget {
  const GifPickerSheet({
    required this.controller,
    required this.onSelected,
    super.key,
  });

  final GifPickerController controller;
  final ValueChanged<String> onSelected;

  static Future<void> show(
    BuildContext context, {
    required GifPickerController controller,
    required ValueChanged<String> onSelected,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surfaces.canvas,
    builder: (_) =>
        GifPickerSheet(controller: controller, onSelected: onSelected),
  );

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final TextEditingController _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    _field.text = widget.controller.query;
    // Deferred for the same reason every other load is: it notifies before its
    // first await, and this runs while the listener above is building.
    scheduleMicrotask(() {
      if (mounted) unawaited(widget.controller.load());
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _pick(String url) {
    widget.onSelected(url);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('gif-search-field'),
              controller: _field,
              autofocus: true,
              onChanged: widget.controller.search,
              onSubmitted: (value) =>
                  unawaited(widget.controller.searchNow(value)),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search Tenor',
              ),
            ),
            if (widget.controller.suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final suggestion in widget.controller.suggestions)
                      ActionChip(
                        key: ValueKey('gif-suggestion-$suggestion'),
                        label: Text(suggestion),
                        onPressed: () {
                          _field.text = suggestion;
                          unawaited(widget.controller.searchNow(suggestion));
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(height: 320, child: _body(context)),
          ],
        ),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    final controller = widget.controller;
    if (controller.isLoading && controller.results.isEmpty) {
      return const Center(
        key: ValueKey('gif-loading'),
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (controller.results.isEmpty && controller.categories.isEmpty) {
      return Center(
        child: Column(
          key: const ValueKey('gif-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              controller.error == null
                  ? 'Nothing matched that.'
                  : 'Discord did not return any GIFs.',
              style: TextStyle(color: context.surfaces.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('gif-retry'),
              onPressed: () => unawaited(
                controller.query.trim().isEmpty
                    ? controller.load()
                    : controller.searchNow(controller.query),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      children: [
        for (final category in controller.categories)
          _CategoryTile(
            category: category,
            onPressed: () => unawaited(controller.searchNow(category.name)),
          ),
        for (final gif in controller.results)
          _GifTile(gif: gif, onPressed: () => _pick(gif.url)),
      ],
    );
  }
}

class _GifTile extends StatelessWidget {
  const _GifTile({required this.gif, required this.onPressed});

  final GifResult gif;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.surfaces.raised,
    borderRadius: BorderRadius.circular(6),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('gif-result-${gif.id}'),
      onTap: onPressed,
      child: Image.network(
        gif.previewUrl,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined, size: 18)),
      ),
    ),
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onPressed});

  final GifCategory category;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.surfaces.raised,
    borderRadius: BorderRadius.circular(6),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('gif-category-${category.name}'),
      onTap: onPressed,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (category.previewUrl.isNotEmpty)
            Image.network(
              category.previewUrl,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
            ),
            child: Center(
              child: Text(
                category.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
