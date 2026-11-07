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

  /// Whether Flucord can complete this screening: every required step is
  /// one it can answer. A required email or phone verification has to be
  /// done in Discord's own client.
  bool get canAccept =>
      fields.every((field) => field.isAnswerable || !field.required);

  /// Whether every required question has an answer. The rules are agreed to
  /// apart from this, with the dialog's box.
  bool get isAnswered => fields.every(
    (field) => field.isRules || !field.required || field.answer != null,
  );

  /// This screening with [answer] given to the field at [index]. A null
  /// answer clears it.
  RulesScreening answer(int index, ScreeningAnswer? answer) => RulesScreening(
    version: version,
    description: description,
    fields: [
      for (final (at, field) in fields.indexed)
        at == index ? field._answered(answer) : field,
    ],
  );
}

/// What the member answered to one written or multiple-choice question.
sealed class ScreeningAnswer {
  const ScreeningAnswer();

  /// A written answer, sent trimmed. Empty text is no answer.
  const factory ScreeningAnswer.text(String text) = ScreeningText;

  /// The index of the picked choice.
  const factory ScreeningAnswer.choice(int index) = ScreeningChoice;
}

final class ScreeningText extends ScreeningAnswer {
  const ScreeningText(this.text);
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ScreeningText && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

final class ScreeningChoice extends ScreeningAnswer {
  const ScreeningChoice(this.index);
  final int index;

  @override
  bool operator ==(Object other) =>
      other is ScreeningChoice && other.index == index;

  @override
  int get hashCode => index.hashCode;
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
    this.placeholder,
    this.answer,
  });

  static const rulesType = 'TERMS';
  static const textInputType = 'TEXT_INPUT';
  static const paragraphType = 'PARAGRAPH';
  static const multipleChoiceType = 'MULTIPLE_CHOICE';

  final String type;
  final String label;
  final bool required;

  /// The rules to agree to, for a [rulesType] field.
  final List<String> rules;

  /// The answers to pick from, for a multiple-choice field.
  final List<String> choices;
  final String? description;

  /// The hint shown in an empty written answer.
  final String? placeholder;

  /// What the member answered here, or null for nothing yet.
  final ScreeningAnswer? answer;

  bool get isRules => type == rulesType;
  bool get isWritten => type == textInputType || type == paragraphType;
  bool get isMultipleChoice => type == multipleChoiceType;

  /// Whether Flucord can answer this step.
  bool get isAnswerable => isRules || isWritten || isMultipleChoice;

  /// The longest written answer Discord takes, or null for a step that is
  /// not written.
  int? get maxLength => switch (type) {
    textInputType => 150,
    paragraphType => 1000,
    _ => null,
  };

  RulesScreeningField _answered(ScreeningAnswer? answer) => RulesScreeningField(
    type: type,
    label: label,
    required: required,
    rules: rules,
    choices: choices,
    description: description,
    placeholder: placeholder,
    answer: switch (answer) {
      ScreeningText(:final text) when text.trim().isEmpty => null,
      _ => answer,
    },
  );
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
