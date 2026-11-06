import 'chat_models.dart' show Member;

/// What a server asks of somebody who just joined it: to agree to its rules
/// (membership screening), and to answer its onboarding questions.
///
/// A capability of the guild-management plane, checked with `is`. A session
/// whose plane does not offer it shows neither step.
abstract interface class GuildJoinGateRepository {
  /// The server's rules, or null when it screens nobody.
  Future<RulesScreening?> loadRulesScreening(String guildId);

  /// Agrees to [screening]. Answers this account's membership as it stands
  /// afterwards, or null when it could not be read back.
  ///
  /// Refusals arrive as [GuildJoinGateRefusal].
  Future<Member?> acceptRules({
    required String guildId,
    required RulesScreening screening,
  });

  /// The questions a new member walks through, or null when the server asks
  /// none.
  Future<GuildOnboarding?> loadOnboarding(String guildId);

  /// Sends the options picked in [onboarding]; every prompt and option in it
  /// counts as seen at [seenAt]. Answers this account's membership as it
  /// stands afterwards, with the roles the answers granted.
  ///
  /// Refusals arrive as [GuildJoinGateRefusal].
  Future<Member?> answerOnboarding({
    required String guildId,
    required GuildOnboarding onboarding,
    required Set<String> chosenOptionIds,
    required DateTime seenAt,
  });
}

/// A server's membership screening, from
/// `GET /guilds/{id}/member-verification`.
final class RulesScreening {
  const RulesScreening({required this.fields, this.version, this.description});

  /// When the screening last changed. Sent back with the answers, so Discord
  /// can refuse answers to rules that changed in the meantime.
  final String? version;

  /// What the server says about itself above the rules.
  final String? description;

  final List<RulesScreeningField> fields;

  /// Every rule the member agrees to, in order.
  List<String> get rules => [
    for (final field in fields)
      if (field.isRules) ...field.rules,
  ];

  /// Whether Flucord can complete this screening. Only the rules can be
  /// agreed to here; a required written or multiple-choice question has to
  /// be answered in Discord's own client.
  bool get canAccept =>
      fields.every((field) => field.isRules || !field.required);
}

/// One step of a screening. [type] is Discord's own name for it, such as
/// `TERMS`.
final class RulesScreeningField {
  const RulesScreeningField({
    required this.type,
    required this.label,
    this.required = false,
    this.rules = const [],
    this.choices = const [],
    this.description,
  });

  static const rulesType = 'TERMS';

  final String type;
  final String label;
  final bool required;

  /// The rules to agree to, for a [rulesType] field.
  final List<String> rules;

  /// The answers to pick from, for a multiple-choice field.
  final List<String> choices;
  final String? description;

  bool get isRules => type == rulesType;
}

/// A server's onboarding, from `GET /guilds/{id}/onboarding`, reduced to the
/// prompts shown while joining.
final class GuildOnboarding {
  const GuildOnboarding({
    required this.guildId,
    required this.prompts,
    this.defaultChannelIds = const [],
  });

  final String guildId;
  final List<OnboardingPrompt> prompts;

  /// Channels every member gets, whatever they answer.
  final List<String> defaultChannelIds;
}

/// One onboarding question.
final class OnboardingPrompt {
  const OnboardingPrompt({
    required this.id,
    required this.title,
    required this.options,
    this.singleSelect = false,
    this.required = false,
  });

  final String id;
  final String title;
  final List<OnboardingOption> options;

  /// Only one option may be picked.
  final bool singleSelect;

  /// An option must be picked before the member can go on.
  final bool required;
}

/// One answer to an [OnboardingPrompt], and what picking it grants.
final class OnboardingOption {
  const OnboardingOption({
    required this.id,
    required this.title,
    this.description,
    this.emoji,
    this.channelIds = const [],
    this.roleIds = const [],
  });

  final String id;
  final String title;
  final String? description;

  /// A Unicode emoji drawn before the title. Null for none or a custom emoji.
  final String? emoji;
  final List<String> channelIds;
  final List<String> roleIds;
}

/// Discord refused a screening or onboarding answer. [message] is what the
/// person reads.
final class GuildJoinGateRefusal implements Exception {
  const GuildJoinGateRefusal(this.message);

  final String message;

  @override
  String toString() => message;
}
