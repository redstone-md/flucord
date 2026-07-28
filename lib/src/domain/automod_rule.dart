/// What a rule watches for.
///
/// The numbers are Discord's and are stored rather than derived: a rule the
/// server returns with a trigger this client has never heard of still has to
/// round-trip through an edit of its name without being silently rewritten
/// into something else.
enum AutoModTriggerType {
  keyword(1),
  spamLink(2),
  mlSpam(3),
  defaultKeywordList(4),
  mentionSpam(5),
  userProfile(6),
  serverPolicy(7),
  unknown(0);

  const AutoModTriggerType(this.code);

  final int code;

  static AutoModTriggerType fromCode(int code) => values.firstWhere(
    (value) => value.code == code,
    orElse: () => AutoModTriggerType.unknown,
  );

  /// Whether the rule carries a list of words the moderator wrote themselves.
  bool get hasKeywords =>
      this == AutoModTriggerType.keyword ||
      this == AutoModTriggerType.userProfile;

  /// Whether a guild may hold more than one rule of this trigger. Discord
  /// allows many keyword rules but exactly one of each of the rest, so a
  /// create form has to know which triggers are already spent.
  bool get allowsMany => hasKeywords;
}

/// When the rule runs. A rule on member updates checks names, not messages.
enum AutoModEventType {
  messageSend(1),
  guildMemberJoinOrUpdate(2),
  unknown(0);

  const AutoModEventType(this.code);

  final int code;

  static AutoModEventType fromCode(int code) => values.firstWhere(
    (value) => value.code == code,
    orElse: () => AutoModEventType.unknown,
  );
}

/// One of Discord's own word lists, which a guild switches on rather than
/// writes: the contents are server-side and are never sent to a client.
enum AutoModKeywordPreset {
  profanity(1),
  sexualContent(2),
  slurs(3),
  unknown(0);

  const AutoModKeywordPreset(this.code);

  final int code;

  static AutoModKeywordPreset fromCode(int code) => values.firstWhere(
    (value) => value.code == code,
    orElse: () => AutoModKeywordPreset.unknown,
  );
}

/// What happens when a rule matches.
enum AutoModActionType {
  blockMessage(1),
  flagToChannel(2),
  userCommunicationDisabled(3),
  quarantineUser(4),
  unknown(0);

  const AutoModActionType(this.code);

  final int code;

  static AutoModActionType fromCode(int code) => values.firstWhere(
    (value) => value.code == code,
    orElse: () => AutoModActionType.unknown,
  );
}

/// One consequence of a match.
///
/// The metadata a consequence carries depends on which one it is — an alert
/// names a channel, a timeout names a duration — so both live here and the
/// irrelevant one stays empty rather than each action type getting a class of
/// its own that the wire format would not distinguish anyway.
final class AutoModAction {
  const AutoModAction({
    required this.type,
    this.channelId = '',
    this.durationSeconds = 0,
    this.customMessage = '',
  });

  final AutoModActionType type;

  /// Where an alert is posted. Empty for every other action.
  final String channelId;

  /// How long a member is timed out for. Discord's ceiling is four weeks.
  final int durationSeconds;

  /// What the member is told when their message is blocked. Empty means
  /// Discord's own wording.
  final String customMessage;

  static const maxTimeout = Duration(days: 28);

  @override
  bool operator ==(Object other) =>
      other is AutoModAction &&
      other.type == type &&
      other.channelId == channelId &&
      other.durationSeconds == durationSeconds &&
      other.customMessage == customMessage;

  @override
  int get hashCode =>
      Object.hash(type, channelId, durationSeconds, customMessage);
}

/// What a trigger matches on.
///
/// Every field is present for every trigger because the wire object is one
/// shape; which fields mean anything is decided by the rule's trigger type.
final class AutoModTriggerMetadata {
  const AutoModTriggerMetadata({
    this.keywordFilter = const [],
    this.regexPatterns = const [],
    this.presets = const [],
    this.allowList = const [],
    this.mentionTotalLimit = 0,
    this.mentionRaidProtectionEnabled = false,
  });

  /// Substrings that trip the rule. Discord allows a leading or trailing `*`
  /// as an anchor; the text is kept exactly as typed so those survive.
  final List<String> keywordFilter;

  /// Rust-flavoured regular expressions, evaluated server-side. Nothing here
  /// compiles them: Dart's dialect differs, and a pattern that this client
  /// accepted but the server rejected would be worse than one refusal.
  final List<String> regexPatterns;

  final List<AutoModKeywordPreset> presets;

  /// Words that survive the filter, including the presets.
  final List<String> allowList;

  /// The number of mentions in one message that trips a mention-spam rule.
  final int mentionTotalLimit;

  final bool mentionRaidProtectionEnabled;

  bool get isEmpty =>
      keywordFilter.isEmpty &&
      regexPatterns.isEmpty &&
      presets.isEmpty &&
      allowList.isEmpty &&
      mentionTotalLimit == 0 &&
      !mentionRaidProtectionEnabled;

  @override
  bool operator ==(Object other) =>
      other is AutoModTriggerMetadata &&
      _sameStrings(other.keywordFilter, keywordFilter) &&
      _sameStrings(other.regexPatterns, regexPatterns) &&
      _samePresets(other.presets, presets) &&
      _sameStrings(other.allowList, allowList) &&
      other.mentionTotalLimit == mentionTotalLimit &&
      other.mentionRaidProtectionEnabled == mentionRaidProtectionEnabled;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(keywordFilter),
    Object.hashAll(regexPatterns),
    Object.hashAll(presets),
    Object.hashAll(allowList),
    mentionTotalLimit,
    mentionRaidProtectionEnabled,
  );

  static bool _sameStrings(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

  static bool _samePresets(
    List<AutoModKeywordPreset> a,
    List<AutoModKeywordPreset> b,
  ) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
}

/// One AutoMod rule as the guild holds it.
final class AutoModRule {
  const AutoModRule({
    required this.id,
    required this.guildId,
    required this.name,
    required this.eventType,
    required this.triggerType,
    this.creatorId = '',
    this.metadata = const AutoModTriggerMetadata(),
    this.actions = const [],
    this.enabled = false,
    this.exemptRoleIds = const [],
    this.exemptChannelIds = const [],
  });

  final String id;
  final String guildId;
  final String name;
  final String creatorId;
  final AutoModEventType eventType;
  final AutoModTriggerType triggerType;
  final AutoModTriggerMetadata metadata;
  final List<AutoModAction> actions;

  /// A disabled rule still exists and still lists its actions; it just does
  /// not run. Discord's own page keeps them visible, greyed out.
  final bool enabled;

  final List<String> exemptRoleIds;
  final List<String> exemptChannelIds;

  bool get blocksMessages =>
      actions.any((action) => action.type == AutoModActionType.blockMessage);

  /// The channel alerts go to, or empty if the rule raises none.
  String get alertChannelId => actions
      .firstWhere(
        (action) => action.type == AutoModActionType.flagToChannel,
        orElse: () => const AutoModAction(type: AutoModActionType.unknown),
      )
      .channelId;

  /// How long the rule times a member out for, or zero if it does not.
  Duration get timeout => Duration(
    seconds: actions
        .firstWhere(
          (action) =>
              action.type == AutoModActionType.userCommunicationDisabled,
          orElse: () => const AutoModAction(type: AutoModActionType.unknown),
        )
        .durationSeconds,
  );
}

/// What a moderator does with one message AutoMod flagged.
///
/// These live on the alert Discord posts to the rule's alert channel, not on
/// the rule, which is why they are an action rather than a setting. Discord
/// checks Manage Messages on the alert channel before offering any of them.
enum AutoModAlertAction {
  /// Mark the alert handled. The alert stays, struck through.
  setCompleted(1),

  /// Take that mark back.
  unsetCompleted(2),

  /// Delete the message that tripped the rule, not the alert about it.
  deleteUserMessage(3),

  /// Tell Discord the rule was wrong about this one.
  submitFeedback(4);

  const AutoModAlertAction(this.code);

  final int code;
}
