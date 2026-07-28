/// One thing Discord has recorded against an account.
///
/// Discord calls these classifications. A guild classification is the same
/// shape with a guild attached — an action taken against a server the account
/// owns rather than against the account.
final class AccountClassification {
  const AccountClassification({
    required this.id,
    this.title = '',
    this.subtitle = '',
    this.guildId = '',
    this.appealEligible = false,
  });

  final String id;

  /// What Discord says it was, in Discord's own words. Empty when the server
  /// sent none: the strings are localised server-side, and inventing one here
  /// would be putting words in Discord's mouth about somebody's record.
  final String title;

  final String subtitle;

  /// The server this was taken against, or empty when it was the account.
  final String guildId;

  /// Whether this particular record can be asked to be looked at again.
  final bool appealEligible;

  bool get isGuild => guildId.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is AccountClassification &&
      other.id == id &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.guildId == guildId &&
      other.appealEligible == appealEligible;

  @override
  int get hashCode => Object.hash(id, title, subtitle, guildId, appealEligible);
}

/// What Discord's safety hub says about this account.
final class AccountStanding {
  const AccountStanding({
    this.username = '',
    this.standing = 0,
    this.classifications = const [],
    this.isDsaEligible = false,
    this.isAppealEligible = false,
  });

  /// The account this describes, as the server names it.
  final String username;

  /// Discord's own numeric state.
  ///
  /// Deliberately not mapped onto named tiers. The desktop bundle ships no
  /// enum for it that static analysis can recover, and inventing labels like
  /// "limited" for numbers nobody verified would be telling somebody their
  /// account is in trouble on a guess.
  final int standing;

  final List<AccountClassification> classifications;

  /// Whether the account may use the Digital Services Act appeal route.
  final bool isDsaEligible;

  /// Whether an appeal may be raised at all, separately from whether any one
  /// record is eligible.
  final bool isAppealEligible;

  /// Nothing on record. The one thing that can be said without reading
  /// Discord's numeric state: an account with no classifications has had
  /// nothing taken against it.
  bool get isClear => classifications.isEmpty;

  /// Records against servers, and records against the account, split apart
  /// because they read as two different lists to the person looking.
  List<AccountClassification> get guildRecords => [
    for (final record in classifications)
      if (record.isGuild) record,
  ];

  List<AccountClassification> get accountRecords => [
    for (final record in classifications)
      if (!record.isGuild) record,
  ];
}

/// Reads the account's standing, and asks for a review of one record.
abstract interface class SafetyHubRepository {
  /// `GET /safety-hub/@me`.
  Future<AccountStanding> loadAccountStanding();

  /// Asks Discord to look at one record again.
  ///
  /// Returns whether the request was accepted. A refusal is not an error: an
  /// account that has already appealed the same record gets a no, and showing
  /// that as a failure would suggest the client broke.
  Future<bool> requestReview(String classificationId);
}
