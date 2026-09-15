import '../../domain/account_entitlements.dart';
import 'discord_rest_client.dart';

/// What the account holds, read from `GET /users/@me/entitlements`.
///
/// Read-only by design: an entitlement is Discord's record of a grant, and
/// the only routes that change it are the commerce ones this client does not
/// carry.
final class DiscordAccountEntitlementsRepository
    implements AccountEntitlementsRepository {
  DiscordAccountEntitlementsRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  Future<AccountEntitlements> loadEntitlements() async => readEntitlements(
    await _rest.getList(
      '/users/@me/entitlements',
      query: const {'with_sku': 'true', 'exclude_ended': 'true'},
    ),
  );

  /// Discord's entitlement type for a premium subscription.
  static const _premiumSubscriptionType = 2;

  /// Discord's entitlement type for a boost bought with premium guild
  /// subscriptions.
  static const _guildPowerupType = 13;

  /// Reads the entitlements payload into what the page shows.
  ///
  /// The premium tier is the highest the grants add up to: Discord can hold
  /// several premium SKUs for one account and the page should name the one
  /// that governs, not the first that arrived.
  static AccountEntitlements readEntitlements(
    List<Map<String, Object?>> payload,
  ) {
    var tier = PremiumTier.none;
    var boosts = 0;
    final entitlements = <AccountEntitlement>[];
    for (final entry in payload) {
      final type = entry['type'];
      if (type is! int) continue;
      if (entry['deleted'] == true) continue;
      final until = _until(entry['ends_at']);
      if (type == _premiumSubscriptionType) {
        final skuTier = _premiumTier(entry['sku']);
        if (skuTier.wireValue > tier.wireValue) tier = skuTier;
        entitlements.add(
          AccountEntitlement(
            id: _id(entry, 'premium'),
            label: _skuName(entry['sku']),
            heldUntil: until,
          ),
        );
      } else if (type == _guildPowerupType) {
        boosts++;
        entitlements.add(
          AccountEntitlement(
            id: _id(entry, 'boost'),
            label: 'Server Boost',
            heldUntil: until,
            isBoost: true,
          ),
        );
      }
    }
    return AccountEntitlements(
      premiumTier: tier,
      boostsHeld: boosts,
      entitlements: entitlements,
    );
  }

  /// Reads the premium tier off the embedded SKU, by the name Discord gives
  /// its own subscription SKUs.
  ///
  /// The SKU's `premium` flag says the grant carries a Nitro perk; the tier
  /// comes from the SKU name, which is the only place Discord spells out
  /// which of its subscriptions this is. A name this build does not
  /// recognise reads as the base tier rather than being guessed higher.
  static PremiumTier _premiumTier(Object? sku) {
    if (sku is! Map || sku['premium'] != true) return PremiumTier.nitroBasic;
    final name = sku['name'];
    if (name is! String) return PremiumTier.nitroBasic;
    if (name.toLowerCase().contains('basic')) return PremiumTier.nitroBasic;
    if (name.toLowerCase().contains('boost')) return PremiumTier.nitroBoost;
    return PremiumTier.nitro;
  }

  static String _skuName(Object? sku) {
    if (sku is Map && sku['name'] is String) {
      final name = sku['name']! as String;
      if (name.isNotEmpty) return name;
    }
    return 'Premium';
  }

  static String _id(Map<String, Object?> entry, String fallback) {
    final id = entry['id'];
    if (id is String && id.isNotEmpty) return id;
    final subscriptionId = entry['subscription_id'];
    return subscriptionId is String && subscriptionId.isNotEmpty
        ? subscriptionId
        : fallback;
  }

  static DateTime? _until(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
