/// One thing the account holds because Discord granted it.
///
/// Read-only: an entitlement is granted by purchase, gift, or promotion, and
/// this client has no part in any of those. Nothing here can change what the
/// account holds; it can only say what that is.
final class AccountEntitlement {
  const AccountEntitlement({
    required this.id,
    required this.label,
    this.heldUntil,
    this.isBoost = false,
  });

  /// Discord's own id for the grant.
  final String id;

  /// The SKU's name as Discord localises it: `Nitro`, `Server Boost`.
  final String label;

  /// When the grant stops holding, or null when it does not expire.
  final DateTime? heldUntil;

  /// A boost the account put into a server.
  final bool isBoost;

  /// Plain words for when this one ends, or that it does not.
  String describeExpiry() {
    final until = heldUntil;
    if (until == null) return 'Does not expire.';
    final date = until.toLocal();
    final month = _months[date.month - 1];
    return 'Held until $month ${date.day}, ${date.year}.';
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}

/// Discord's own buckets for a premium subscription, read off the account's
/// entitlements. The names are Discord's; a client that renamed them would be
/// answering a question about somebody's purchase with wording of its own.
enum PremiumTier {
  none(0, 'No Nitro'),
  nitroBasic(1, 'Nitro Basic'),
  nitro(2, 'Nitro'),
  nitroBoost(3, 'Nitro with Boost');

  const PremiumTier(this.wireValue, this.label);

  /// Discord's `premium_type` on the account, which the entitlements imply.
  final int wireValue;
  final String label;

  static PremiumTier fromWire(Object? value) => switch (value) {
    1 => nitroBasic,
    2 => nitro,
    3 => nitroBoost,
    _ => none,
  };

  /// The longest message this account may type, in characters.
  ///
  /// Nitro Basic leaves the length where the free plan has it; only the full
  /// subscription doubles it.
  int get messageCharacterLimit => switch (this) {
    PremiumTier.nitro || PremiumTier.nitroBoost => 4000,
    _ => 2000,
  };

  /// The largest file this account may attach anywhere, in bytes.
  int get uploadLimitBytes => switch (this) {
    PremiumTier.none => 20 * 1024 * 1024,
    PremiumTier.nitroBasic => 50 * 1024 * 1024,
    PremiumTier.nitro || PremiumTier.nitroBoost => 500 * 1024 * 1024,
  };
}

/// The upload limits a server hands every member, from its boost level.
///
/// Discord's `premium_tier` on the guild: level 1 changes nothing here, and
/// levels 2 and 3 raise the limit for everybody in the server, held
/// separately from whatever the account itself can attach elsewhere.
abstract final class GuildUploadLimits {
  static const level2 = 50 * 1024 * 1024;
  static const level3 = 100 * 1024 * 1024;

  /// The largest file this account may attach in a server at
  /// [guildTier], in bytes.
  static int uploadLimitFor({
    required int guildTier,
    required PremiumTier tier,
  }) {
    final byGuild = switch (guildTier) {
      2 => level2,
      3 => level3,
      _ => 0,
    };
    return byGuild > tier.uploadLimitBytes ? byGuild : tier.uploadLimitBytes;
  }
}

/// What the account holds, and what each thing changes.
///
/// The perks stated beside a tier are the ones Discord itself names for it,
/// kept to what this client can show happening: upload limits, emoji reach,
/// stream quality. No commerce: nothing here offers a purchase, and the
/// display says only what the account already has.
final class AccountEntitlements {
  const AccountEntitlements({
    this.premiumTier = PremiumTier.none,
    this.boostsHeld = 0,
    this.entitlements = const [],
  });

  /// The premium subscription the entitlements add up to.
  final PremiumTier premiumTier;

  /// How many server boosts this account holds. Boosts are also listed one by
  /// one in [entitlements]; this is the count a summary row reads.
  final int boostsHeld;

  /// Every grant the account holds, in the order Discord listed them.
  final List<AccountEntitlement> entitlements;

  bool get hasNothing =>
      premiumTier == PremiumTier.none &&
      boostsHeld == 0 &&
      entitlements.isEmpty;

  /// What the premium tier changes, in plain words. Empty for none, because
  /// listing what an account without Nitro does not get would be a sales
  /// pitch, and there is no selling here.
  List<String> get premiumPerks => switch (premiumTier) {
    PremiumTier.none => const [],
    PremiumTier.nitroBasic => const [
      'Bigger uploads.',
      'Custom emoji from your other servers.',
      'Nitro badge on your profile.',
    ],
    PremiumTier.nitro || PremiumTier.nitroBoost => const [
      'Bigger uploads.',
      'Custom emoji and stickers from your other servers.',
      'HD streaming.',
      'Two boosts of your own.',
    ],
  };
}

/// Reads what the account holds. There is no write path and no commerce.
abstract interface class AccountEntitlementsRepository {
  /// `GET /users/@me/entitlements` with the SKU included.
  Future<AccountEntitlements> loadEntitlements();
}
