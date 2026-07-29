/// What Discord's family centre reports about this account.
///
/// Read-only but for one thing: asking for the code that links a parent to a
/// teenager. Nothing here can change what a linked account may do — those
/// controls live on the teenager's own settings, which this session is not.
final class FamilyCentre {
  const FamilyCentre({
    this.ageGroup = '',
    this.linkedUserIds = const [],
    this.userNames = const {},
    this.activity,
  });

  /// Discord's own bucket for the account's age. Carried verbatim: the values
  /// are Discord's to define and a client that renamed them would be
  /// answering a legal question it has no standing to answer.
  final String ageGroup;

  /// The accounts linked to this one, in the order Discord listed them.
  final List<String> linkedUserIds;

  /// Display names for whoever the payload named, so a linked account reads
  /// as a person rather than as a snowflake.
  final Map<String, String> userNames;

  /// The activity summary, or null when Discord sent none — which is what an
  /// account with no linked teenager gets.
  final TeenActivitySummary? activity;

  bool get hasLinkedUsers => linkedUserIds.isNotEmpty;

  /// A name for [userId], falling back to the id so a row is never blank.
  String nameFor(String userId) => userNames[userId] ?? userId;
}

/// What a linked teenager has been doing, as Discord summarises it.
///
/// Deliberately counts only. Discord's family centre reports totals per kind
/// of activity and never the content — no messages, no call audio — and this
/// carries the same limit rather than reaching for more.
final class TeenActivitySummary {
  const TeenActivitySummary({
    this.teenUserId = '',
    this.totals = const {},
    this.userIds = const [],
    this.guildIds = const [],
  });

  final String teenUserId;

  /// How many of each kind of thing, keyed by Discord's own name for it.
  final Map<String, int> totals;

  /// Who they spoke to, and which servers they were active in.
  final List<String> userIds;
  final List<String> guildIds;

  bool get isEmpty => totals.isEmpty && userIds.isEmpty && guildIds.isEmpty;

  /// The total across every kind, for a surface that wants one number.
  int get totalActions =>
      totals.values.fold(0, (sum, value) => sum + (value < 0 ? 0 : value));
}

/// Reads the family centre and asks for a link code.
/// What a parent may see about a linked teen account.
///
/// Read-only here. Discord writes these through the teen's own settings-proto,
/// a different blob from the account's own with its own permission model, and
/// a client that guessed at that write would be changing what somebody else's
/// account is allowed to do.
final class TeenControls {
  const TeenControls({
    this.userId = '',
    this.settings = const {},
    this.consents = const {},
  });

  final String userId;

  /// The restrictions, as Discord names them. Carried verbatim: these are
  /// controls over another person's account, and renaming one in the surface
  /// would tell a parent they had set something other than what they set.
  final Map<String, bool> settings;

  /// What the teen has agreed to, by the same rule.
  final Map<String, bool> consents;

  bool get isEmpty => settings.isEmpty && consents.isEmpty;
}

abstract interface class FamilyCentreRepository {
  /// `GET /family-center/@me`.
  Future<FamilyCentre> loadFamilyCentre();

  /// `GET /family-center/{teenId}/settings-and-consents`.
  ///
  /// Answers empty controls for a link the parent may not read, which is an
  /// answer rather than a fault: a teen can unlink at any time.
  Future<TeenControls> loadTeenControls(String teenId);

  /// Asks for the code a parent enters to link to this account.
  ///
  /// Returns the code, or null when Discord declines to issue one — which it
  /// does for an account that is not eligible, and which is an answer rather
  /// than a failure.
  Future<String?> requestLinkCode();
}
