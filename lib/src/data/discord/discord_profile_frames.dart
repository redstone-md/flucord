import '../../domain/profile_frame.dart';
import 'discord_cdn.dart';

/// Reads profile frames out of the shop's product answer
/// (`GET /storefront/products/skus`).
///
/// A product holds every colour of a frame, and each colour is a SKU of its
/// own: `products[].skus[]`, with the frame's description in its
/// `tenant_metadata.collectibles.item`. A profile names the colour's SKU.
abstract final class DiscordProfileFrames {
  /// How the frame [skuId] looks, or null where the answer does not
  /// describe it or describes it without a picture.
  static ProfileFrameConfig? read(Map<String, Object?> payload, String skuId) {
    for (final product in _maps(payload['products'])) {
      for (final sku in _maps(product['skus'])) {
        if (sku['id'] != skuId) continue;
        final item = switch (sku['tenant_metadata']) {
          {'collectibles': {'item': final Map<Object?, Object?> item}} =>
            item.cast<String, Object?>(),
          _ => null,
        };
        if (item == null || item['type'] != ProfileFrame.collectibleType) {
          return null;
        }
        return _config(item, skuId);
      }
    }
    return null;
  }

  static ProfileFrameConfig? _config(Map<String, Object?> item, String skuId) {
    final innerWidth = _number(item['inner_width']);
    final layers = [
      for (final layer in _maps(item['layers']))
        if ((layer['id'], _anchor(layer['anchor'])) case (
          final String id,
          final anchor?,
        ))
          if (DiscordCdn.profileFrameLayer(skuId, id) case final src?)
            ProfileFrameLayer(
              src: src,
              anchor: anchor,
              inFront: layer['order'] != 'back',
            ),
    ];
    if (innerWidth <= 0 || layers.isEmpty) return null;
    return ProfileFrameConfig(
      innerWidth: innerWidth,
      overflowTop: _number(item['overflow_top']),
      overflowBottom: _number(item['overflow_bottom']),
      overflowHorizontal: _number(item['overflow_horizontal']),
      layers: layers,
    );
  }

  static ProfileFrameAnchor? _anchor(Object? value) => switch (value) {
    'top' => ProfileFrameAnchor.top,
    'bottom' => ProfileFrameAnchor.bottom,
    'center' => ProfileFrameAnchor.center,
    _ => null,
  };

  static double _number(Object? value) => value is num ? value.toDouble() : 0;

  static Iterable<Map<String, Object?>> _maps(Object? value) => [
    if (value is List)
      for (final entry in value)
        if (entry is Map) entry.cast<String, Object?>(),
  ];
}
