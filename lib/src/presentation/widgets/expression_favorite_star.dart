import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/expression_favorites_controller.dart';

/// The star that sits on a GIF, sticker or emoji tile.
///
/// Drawn on the tile rather than beside it, because the pickers lay their
/// items out in a grid where a second row of controls would halve how much is
/// on screen. It only appears once the transport can hold favourites at all —
/// a star that silently did nothing would be worse than no star.
class ExpressionFavoriteStar extends StatelessWidget {
  const ExpressionFavoriteStar({
    required this.controller,
    required this.isFavorite,
    required this.onPressed,
    super.key,
  });

  final ExpressionFavoritesController controller;
  final bool isFavorite;

  /// Returns whether the change was taken; `false` means a limit refused it.
  final Future<bool> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported) return const SizedBox.shrink();
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => unawaited(_press(context)),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            isFavorite ? Icons.star : Icons.star_border,
            size: 16,
            color: isFavorite ? Colors.amber : Colors.white,
            semanticLabel: isFavorite ? 'Unfavourite' : 'Favourite',
          ),
        ),
      ),
    );
  }

  Future<void> _press(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await onPressed()) return;
    // Refused, not failed: Discord holds 250 of each, and GIFs until the
    // stored group runs out of room. Saying which is why the star did nothing
    // beats leaving it unchanged with no explanation.
    messenger?.showSnackBar(
      const SnackBar(
        key: ValueKey('favorite-refused'),
        content: Text('Discord would not hold another favourite.'),
      ),
    );
  }
}
