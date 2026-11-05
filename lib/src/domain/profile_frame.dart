/// The profile frame somebody wears: the item of type 3 in a profile's
/// `collectibles`. The profile names it by SKU only; how it looks comes
/// from the shop ([ProfileFrameConfig]).
final class ProfileFrame {
  const ProfileFrame({required this.skuId, this.expiresAt});

  static const collectibleType = 3;

  /// The frame among a `collectibles` list, or null where none is worn.
  static ProfileFrame? fromCollectibles(Object? json) {
    if (json is! List) return null;
    for (final item in json) {
      if (item is! Map || item['type'] != collectibleType) continue;
      final skuId = item['sku_id'];
      if (skuId is! String || skuId.isEmpty) continue;
      final expiresAt = item['expires_at'];
      return ProfileFrame(
        skuId: skuId,
        // Unix seconds, or null for a frame that does not expire.
        expiresAt: expiresAt is int
            ? DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true)
            : null,
      );
    }
    return null;
  }

  final String skuId;
  final DateTime? expiresAt;

  bool isWornAt(DateTime now) => expiresAt?.isAfter(now) ?? true;
}

/// How a frame looks: its pictures and how far they reach past the card.
///
/// Lengths are in the frame's own units, where the card is [innerWidth]
/// wide. Scaled to a card, the frame overhangs it by [overflowHorizontal]
/// on each side, [overflowTop] above and [overflowBottom] below.
final class ProfileFrameConfig {
  const ProfileFrameConfig({
    required this.innerWidth,
    required this.layers,
    this.overflowTop = 0,
    this.overflowBottom = 0,
    this.overflowHorizontal = 0,
  });

  final double innerWidth;
  final double overflowTop;
  final double overflowBottom;
  final double overflowHorizontal;

  /// In Discord's order, which is the order they are drawn in.
  final List<ProfileFrameLayer> layers;
}

/// Where a frame picture sits in the frame's box: along its top edge, along
/// its bottom edge, or over all of it.
enum ProfileFrameAnchor { top, bottom, center }

/// One picture of a frame. It is as wide as the frame's box, and keeps its
/// own proportions, except a [ProfileFrameAnchor.center] one, which fills
/// the box.
final class ProfileFrameLayer {
  const ProfileFrameLayer({
    required this.src,
    required this.anchor,
    this.inFront = true,
  });

  final String src;
  final ProfileFrameAnchor anchor;

  /// Over the card's content (`front`), or behind the card (`back`).
  final bool inFront;
}
