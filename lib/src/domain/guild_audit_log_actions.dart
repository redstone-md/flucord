part of 'guild_audit_log.dart';

/// Whether an action created, changed or removed something.
///
/// Derived on this side. The API never sends it — the renderer switches over
/// the action id — so a client that waited for a field would render every entry
/// as "changed".
enum AuditLogActionClass { create, update, delete, other }

/// What an entry's `target_id` points at.
///
/// Also derived, and by range comparison rather than a table, which is why the
/// gaps in [AuditLogActionType] matter: an id Discord adds inside an existing
/// range takes that range's target type, and one past the end is honestly
/// [unknown] rather than mislabelled.
enum AuditLogTargetType {
  all,
  guild,
  channel,
  channelOverwrite,
  user,
  role,
  invite,
  webhook,
  emoji,
  integration,
  stageInstance,
  sticker,
  scheduledEvent,
  thread,
  applicationCommand,
  soundboard,
  autoModerationRule,
  onboardingPrompt,
  guildOnboarding,
  guildHome,
  homeSettings,
  voiceChannelStatus,
  scheduledEventException,
  memberVerification,
  guildProfile,
  unknown,
}

/// Discord's audit-log `action_type`, complete as of build 1.0.9249.
///
/// The gaps are real, not omissions: there is no 63–71, 120, 122–129, 133–139,
/// 147–149, 152–162, 168–170, 173–179, 181–189, 194–199 or 203–209.
enum AuditLogActionType {
  guildUpdate(1),
  channelCreate(10),
  channelUpdate(11),
  channelDelete(12),
  channelOverwriteCreate(13),
  channelOverwriteUpdate(14),
  channelOverwriteDelete(15),
  memberKick(20),
  memberPrune(21),
  memberBanAdd(22),
  memberBanRemove(23),
  memberUpdate(24),
  memberRoleUpdate(25),
  memberMove(26),
  memberDisconnect(27),
  botAdd(28),
  roleCreate(30),
  roleUpdate(31),
  roleDelete(32),
  inviteCreate(40),
  inviteUpdate(41),
  inviteDelete(42),
  webhookCreate(50),
  webhookUpdate(51),
  webhookDelete(52),
  emojiCreate(60),
  emojiUpdate(61),
  emojiDelete(62),
  messageDelete(72),
  messageBulkDelete(73),
  messagePin(74),
  messageUnpin(75),
  integrationCreate(80),
  integrationUpdate(81),
  integrationDelete(82),
  stageInstanceCreate(83),
  stageInstanceUpdate(84),
  stageInstanceDelete(85),
  stickerCreate(90),
  stickerUpdate(91),
  stickerDelete(92),
  guildScheduledEventCreate(100),
  guildScheduledEventUpdate(101),
  guildScheduledEventDelete(102),
  threadCreate(110),
  threadUpdate(111),
  threadDelete(112),
  applicationCommandPermissionUpdate(121),
  soundboardSoundCreate(130),
  soundboardSoundUpdate(131),
  soundboardSoundDelete(132),
  autoModerationRuleCreate(140),
  autoModerationRuleUpdate(141),
  autoModerationRuleDelete(142),
  autoModerationBlockMessage(143),
  autoModerationFlagToChannel(144),
  autoModerationUserCommunicationDisabled(145),
  autoModerationQuarantineUser(146),
  creatorMonetizationRequestCreated(150),
  creatorMonetizationTermsAccepted(151),
  onboardingPromptCreate(163),
  onboardingPromptUpdate(164),
  onboardingPromptDelete(165),
  onboardingCreate(166),
  onboardingUpdate(167),
  guildHomeFeatureItem(171),
  guildHomeRemoveItem(172),
  harmfulLinksBlockedMessage(180),
  homeSettingsCreate(190),
  homeSettingsUpdate(191),
  voiceChannelStatusCreate(192),
  voiceChannelStatusDelete(193),
  guildScheduledEventExceptionCreate(200),
  guildScheduledEventExceptionUpdate(201),
  guildScheduledEventExceptionDelete(202),
  guildMemberVerificationUpdate(210),
  guildProfileUpdate(211),
  guildMigratePinPermission(212),
  guildMigrateBypassSlowmodePermission(213);

  const AuditLogActionType(this.wireValue);

  final int wireValue;

  static AuditLogActionType? fromWire(Object? value) {
    final wire = switch (value) {
      final int raw => raw,
      final String raw => int.tryParse(raw),
      _ => null,
    };
    if (wire == null) return null;
    for (final candidate in values) {
      if (candidate.wireValue == wire) return candidate;
    }
    return null;
  }

  AuditLogActionClass get actionClass => switch (this) {
    channelCreate ||
    channelOverwriteCreate ||
    memberBanAdd ||
    botAdd ||
    roleCreate ||
    inviteCreate ||
    webhookCreate ||
    emojiCreate ||
    integrationCreate ||
    stageInstanceCreate ||
    stickerCreate ||
    guildScheduledEventCreate ||
    threadCreate ||
    soundboardSoundCreate ||
    autoModerationRuleCreate ||
    creatorMonetizationRequestCreated ||
    onboardingPromptCreate ||
    onboardingCreate ||
    homeSettingsCreate ||
    voiceChannelStatusCreate ||
    guildScheduledEventExceptionCreate ||
    messagePin => AuditLogActionClass.create,
    channelDelete ||
    channelOverwriteDelete ||
    memberKick ||
    memberPrune ||
    memberBanRemove ||
    memberDisconnect ||
    roleDelete ||
    inviteDelete ||
    webhookDelete ||
    emojiDelete ||
    messageDelete ||
    messageBulkDelete ||
    messageUnpin ||
    integrationDelete ||
    stageInstanceDelete ||
    stickerDelete ||
    guildScheduledEventDelete ||
    threadDelete ||
    soundboardSoundDelete ||
    autoModerationRuleDelete ||
    onboardingPromptDelete ||
    guildHomeRemoveItem ||
    voiceChannelStatusDelete ||
    guildScheduledEventExceptionDelete => AuditLogActionClass.delete,
    guildUpdate ||
    channelUpdate ||
    channelOverwriteUpdate ||
    memberUpdate ||
    memberRoleUpdate ||
    memberMove ||
    roleUpdate ||
    inviteUpdate ||
    webhookUpdate ||
    emojiUpdate ||
    integrationUpdate ||
    stageInstanceUpdate ||
    stickerUpdate ||
    guildScheduledEventUpdate ||
    threadUpdate ||
    applicationCommandPermissionUpdate ||
    soundboardSoundUpdate ||
    autoModerationRuleUpdate ||
    onboardingPromptUpdate ||
    onboardingUpdate ||
    homeSettingsUpdate ||
    guildScheduledEventExceptionUpdate ||
    guildMemberVerificationUpdate ||
    guildProfileUpdate => AuditLogActionClass.update,
    _ => AuditLogActionClass.other,
  };

  /// The renderer's range ladder, in its own order. Rewriting it as a lookup
  /// table would lose the property that makes it useful: an action id Discord
  /// slots into an existing range is classified correctly without a code
  /// change.
  AuditLogTargetType get targetType {
    final id = wireValue;
    if (id <= 1) return AuditLogTargetType.guild;
    if (id <= 12 || id == 73) return AuditLogTargetType.channel;
    if (id <= 15) return AuditLogTargetType.channelOverwrite;
    if (id <= 28 || id == 72 || id == 74 || id == 75) {
      return AuditLogTargetType.user;
    }
    if (id <= 32) return AuditLogTargetType.role;
    if (id <= 42) return AuditLogTargetType.invite;
    if (id <= 52) return AuditLogTargetType.webhook;
    if (id <= 62) return AuditLogTargetType.emoji;
    if (id <= 82) return AuditLogTargetType.integration;
    if (id <= 85) return AuditLogTargetType.stageInstance;
    if (id <= 92) return AuditLogTargetType.sticker;
    if (id <= 102) return AuditLogTargetType.scheduledEvent;
    if (id <= 112) return AuditLogTargetType.thread;
    if (id == 121) return AuditLogTargetType.applicationCommand;
    if (id <= 132) return AuditLogTargetType.soundboard;
    if (id < 143) return AuditLogTargetType.autoModerationRule;
    if (id <= 146) return AuditLogTargetType.user;
    if (id <= 151) return AuditLogTargetType.guild;
    if (id <= 165) return AuditLogTargetType.onboardingPrompt;
    if (id <= 167) return AuditLogTargetType.guildOnboarding;
    if (id <= 172) return AuditLogTargetType.guildHome;
    if (id <= 180) return AuditLogTargetType.guild;
    if (id <= 191) return AuditLogTargetType.homeSettings;
    if (id <= 193) return AuditLogTargetType.voiceChannelStatus;
    if (id <= 202) return AuditLogTargetType.scheduledEventException;
    if (id <= 210) return AuditLogTargetType.memberVerification;
    if (id <= 211) return AuditLogTargetType.guildProfile;
    if (id <= 213) return AuditLogTargetType.guild;
    return AuditLogTargetType.unknown;
  }
}
