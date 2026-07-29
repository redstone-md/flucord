import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/expression_favorites_controller.dart';
import '../../application/gif_picker_controller.dart';
import '../../domain/expression_favorites.dart';
import '../../domain/gif_picker.dart';
import '../../theme/flucord_theme.dart';
import 'expression_favorite_star.dart';

/// The composer's GIF button, and the sheet it opens.
class GifPickerButton extends StatelessWidget {
  const GifPickerButton({
    required this.controller,
    required this.onSelected,
    this.favorites,
    super.key,
  });

  final GifPickerController controller;

  /// The favourites store, when the transport has one.
  final ExpressionFavoritesController? favorites;

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
          favorites: favorites,
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
    this.favorites,
    super.key,
  });

  final GifPickerController controller;
  final ValueChanged<String> onSelected;
  final ExpressionFavoritesController? favorites;

  static Future<void> show(
    BuildContext context, {
    required GifPickerController controller,
    required ValueChanged<String> onSelected,
    ExpressionFavoritesController? favorites,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surfaces.canvas,
    builder: (_) => GifPickerSheet(
      controller: controller,
      onSelected: onSelected,
      favorites: favorites,
    ),
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
      if (!mounted) return;
      unawaited(widget.controller.load());
      // Fetched here because nothing else does: the favourites blob is not in
      // READY, so the starred row would stay empty until something asked.
      unawaited(widget.favorites?.load());
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
    listenable: Listenable.merge([widget.controller, widget.favorites]),
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
    final favorites = widget.favorites;
    // Only on the idle picker: a search is a question about Tenor, and
    // answering it with what was starred last week would bury the results.
    final starred = controller.query.trim().isEmpty && favorites != null
        ? favorites.favorites.gifs
        : const <FavoriteGif>[];
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      children: [
        for (final gif in starred)
          _FavoriteGifTile(
            gif: gif,
            favorites: favorites!,
            onPressed: () => _pick(gif.url),
          ),
        for (final category in controller.categories)
          _CategoryTile(
            category: category,
            onPressed: () => unawaited(controller.searchNow(category.name)),
          ),
        for (final gif in controller.results)
          _GifTile(
            gif: gif,
            favorites: favorites,
            onPressed: () => _pick(gif.url),
          ),
      ],
    );
  }
}

class _GifTile extends StatelessWidget {
  const _GifTile({
    required this.gif,
    required this.favorites,
    required this.onPressed,
  });

  final GifResult gif;
  final ExpressionFavoritesController? favorites;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _TileFrame(
    onPressed: onPressed,
    tileKey: ValueKey('gif-result-${gif.id}'),
    image: gif.previewUrl,
    star: favorites == null
        ? null
        : ExpressionFavoriteStar(
            key: ValueKey('gif-star-${gif.id}'),
            controller: favorites!,
            isFavorite: favorites!.isFavoriteGif(gif.url),
            onPressed: () => favorites!.toggleGif(
              FavoriteGif(
                url: gif.url,
                src: gif.url,
                format: FavoriteGifFormat.fromMediaType(gif.format),
                width: gif.width,
                height: gif.height,
              ),
            ),
          ),
  );
}

/// One already-starred GIF, drawn from the blob rather than from a search.
class _FavoriteGifTile extends StatelessWidget {
  const _FavoriteGifTile({
    required this.gif,
    required this.favorites,
    required this.onPressed,
  });

  final FavoriteGif gif;
  final ExpressionFavoritesController favorites;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _TileFrame(
    onPressed: onPressed,
    tileKey: ValueKey('gif-favorite-${gif.url}'),
    image: gif.src,
    star: ExpressionFavoriteStar(
      key: ValueKey('gif-favorite-star-${gif.url}'),
      controller: favorites,
      isFavorite: true,
      onPressed: () => favorites.toggleGif(gif),
    ),
  );
}

/// The shared body of both tiles: the artwork, and a star pinned to it.
class _TileFrame extends StatelessWidget {
  const _TileFrame({
    required this.tileKey,
    required this.image,
    required this.onPressed,
    this.star,
  });

  final Key tileKey;
  final String image;
  final VoidCallback onPressed;
  final Widget? star;

  @override
  Widget build(BuildContext context) => Material(
    color: context.surfaces.raised,
    borderRadius: BorderRadius.circular(6),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      fit: StackFit.expand,
      children: [
        InkWell(
          key: tileKey,
          onTap: onPressed,
          child: Image.network(
            image,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined, size: 18)),
          ),
        ),
        if (star case final Widget star)
          Positioned(top: 2, right: 2, child: star),
      ],
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
