import '../../domain/profile_effect.dart';

/// Reads a profile effect out of the shop's product for it
/// (`GET /collectibles-products/{sku}`), whose items describe what it sells.
abstract final class DiscordProfileEffects {
  /// How the effect [skuId] looks, or null where the product does not
  /// describe it.
  static ProfileEffectConfig? read(Map<String, Object?> product, String skuId) {
    final items = product['items'];
    if (items is! List) return null;
    for (final item in items) {
      if (item is Map &&
          item['type'] == ProfileEffect.collectibleType &&
          item['sku_id'] == skuId) {
        return ProfileEffectConfig.fromJson(item.cast<String, Object?>());
      }
    }
    return null;
  }
}
