/// Discord's permission bitfield and the masks its own client derives from it.
///
/// Every value is a [BigInt] rather than an `int` on purpose: the field is
/// already 54 bits wide, `MANAGE_OFFICIAL_MESSAGES` alone is `2^53`, and the
/// wire form is a decimal *string* precisely because the number outgrows a
/// double. Truncating to `int` would silently drop the newest bits — the ones
/// this client most needs, since `PIN_MESSAGES`, `SEND_POLLS` and
/// `USE_EXTERNAL_APPS` all live above bit 48.
abstract final class DiscordPermissions {
  static BigInt _bit(int index) => BigInt.one << index;

  // The named bits, in wire order. Bit 47 is deliberately absent: Discord's
  // own constant table skips it and no name for it exists, so inventing one
  // would put a value on the wire that no server agrees with.
  static final createInstantInvite = _bit(0);
  static final kickMembers = _bit(1);
  static final banMembers = _bit(2);
  static final administrator = _bit(3);
  static final manageChannels = _bit(4);
  static final manageGuild = _bit(5);
  static final addReactions = _bit(6);
  static final viewAuditLog = _bit(7);
  static final prioritySpeaker = _bit(8);
  static final stream = _bit(9);
  static final viewChannel = _bit(10);
  static final sendMessages = _bit(11);
  static final sendTtsMessages = _bit(12);
  static final manageMessages = _bit(13);
  static final embedLinks = _bit(14);
  static final attachFiles = _bit(15);
  static final readMessageHistory = _bit(16);
  static final mentionEveryone = _bit(17);
  static final useExternalEmojis = _bit(18);
  static final viewGuildAnalytics = _bit(19);
  static final connect = _bit(20);
  static final speak = _bit(21);
  static final muteMembers = _bit(22);
  static final deafenMembers = _bit(23);
  static final moveMembers = _bit(24);
  static final useVoiceActivity = _bit(25);
  static final changeNickname = _bit(26);
  static final manageNicknames = _bit(27);
  static final manageRoles = _bit(28);
  static final manageWebhooks = _bit(29);
  static final manageGuildExpressions = _bit(30);
  static final useApplicationCommands = _bit(31);
  static final requestToSpeak = _bit(32);
  static final manageEvents = _bit(33);
  static final manageThreads = _bit(34);
  static final createPublicThreads = _bit(35);
  static final createPrivateThreads = _bit(36);
  static final useExternalStickers = _bit(37);
  static final sendMessagesInThreads = _bit(38);
  static final useEmbeddedActivities = _bit(39);
  static final moderateMembers = _bit(40);
  static final viewCreatorMonetizationAnalytics = _bit(41);
  static final useSoundboard = _bit(42);
  static final createGuildExpressions = _bit(43);
  static final createEvents = _bit(44);
  static final useExternalSounds = _bit(45);
  static final sendVoiceMessages = _bit(46);
  static final setVoiceChannelStatus = _bit(48);
  static final sendPolls = _bit(49);
  static final useExternalApps = _bit(50);
  static final pinMessages = _bit(51);
  static final bypassSlowmode = _bit(52);
  static final manageOfficialMessages = _bit(53);

  /// The no-permission sentinel. Also what a deleted or unreadable channel
  /// resolves to.
  static final none = BigInt.zero;

  /// Every named bit. Substituted wholesale for an `ADMINISTRATOR` holder and
  /// for the guild owner, which is why it must not include the unnamed bit 47.
  static final all = combine([
    createInstantInvite,
    kickMembers,
    banMembers,
    administrator,
    manageChannels,
    manageGuild,
    addReactions,
    viewAuditLog,
    prioritySpeaker,
    stream,
    viewChannel,
    sendMessages,
    sendTtsMessages,
    manageMessages,
    embedLinks,
    attachFiles,
    readMessageHistory,
    mentionEveryone,
    useExternalEmojis,
    viewGuildAnalytics,
    connect,
    speak,
    muteMembers,
    deafenMembers,
    moveMembers,
    useVoiceActivity,
    changeNickname,
    manageNicknames,
    manageRoles,
    manageWebhooks,
    manageGuildExpressions,
    useApplicationCommands,
    requestToSpeak,
    manageEvents,
    manageThreads,
    createPublicThreads,
    createPrivateThreads,
    useExternalStickers,
    sendMessagesInThreads,
    useEmbeddedActivities,
    moderateMembers,
    viewCreatorMonetizationAnalytics,
    useSoundboard,
    createGuildExpressions,
    createEvents,
    useExternalSounds,
    sendVoiceMessages,
    setVoiceChannelStatus,
    sendPolls,
    useExternalApps,
    pinMessages,
    bypassSlowmode,
    manageOfficialMessages,
  ]);

  /// What a brand new `@everyone` role holds, and the base Discord falls back
  /// to when the `@everyone` role record itself is missing.
  static final defaultEveryone = combine([
    createInstantInvite,
    changeNickname,
    viewChannel,
    sendMessages,
    embedLinks,
    attachFiles,
    readMessageHistory,
    mentionEveryone,
    useExternalEmojis,
    useExternalStickers,
    addReactions,
    createPublicThreads,
    createPrivateThreads,
    sendMessagesInThreads,
    sendPolls,
    connect,
    speak,
    useVoiceActivity,
    stream,
    useEmbeddedActivities,
    useSoundboard,
    requestToSpeak,
    useApplicationCommands,
    createGuildExpressions,
    createEvents,
    useExternalApps,
  ]);

  /// Clamp for a member who is lurking or has not finished membership
  /// screening: they may look, and nothing else.
  static final lurker = combine([viewChannel, readMessageHistory]);

  /// Clamp for a member whose `communication_disabled_until` is in the future.
  static final timeout = combine([viewChannel, readMessageHistory]);

  /// Clamp for an automod-quarantined member.
  static final quarantine = combine([
    viewChannel,
    readMessageHistory,
    changeNickname,
  ]);

  /// Clamp for a guest member (member flag `IS_GUEST`).
  static final guest = combine([
    viewChannel,
    sendMessages,
    connect,
    speak,
    stream,
    useEmbeddedActivities,
    useExternalApps,
    useExternalEmojis,
    useExternalSounds,
    useExternalStickers,
    useSoundboard,
    useVoiceActivity,
    sendMessagesInThreads,
    embedLinks,
    attachFiles,
    addReactions,
  ]);

  /// Bits Discord withholds from an account without two-factor auth in a guild
  /// whose `mfa_level` is elevated.
  static final mfaGated = combine([
    kickMembers,
    banMembers,
    administrator,
    manageChannels,
    manageGuild,
    manageRoles,
    manageMessages,
    manageThreads,
    moderateMembers,
  ]);

  /// Reads a wire permission value.
  ///
  /// Absent, null, or unparseable fields decode to zero, matching Discord's own
  /// `BigInt(0)` sentinel — a malformed field must not be mistaken for a grant.
  static BigInt parse(Object? value) => tryParse(value) ?? none;

  /// Reads a wire permission value, or null when the field carried nothing
  /// usable. Callers that must distinguish "nobody may do anything" from "we
  /// were never told" need this rather than [parse].
  static BigInt? tryParse(Object? value) {
    final bits = switch (value) {
      final BigInt raw => raw,
      final int raw => BigInt.from(raw),
      final String raw => BigInt.tryParse(raw),
      _ => null,
    };
    // A permission bitfield is unsigned on the wire. A negative value has every
    // bit set under two's complement, so `hasAll` would answer true for
    // ADMINISTRATOR and every other bit — a malformed or hostile field would
    // fail open into full permissions. Refuse it instead.
    if (bits == null || bits.isNegative) return null;
    return bits;
  }

  /// The wire form: a decimal string, whatever the magnitude.
  static String encode(BigInt permissions) => permissions.toString();

  /// True when every bit of [mask] is present. This is the single-permission
  /// test; for a multi-bit mask it is deliberately stricter than [hasAny].
  static bool hasAll(BigInt permissions, BigInt mask) =>
      permissions & mask == mask;

  /// True when at least one bit of [mask] is present.
  static bool hasAny(BigInt permissions, BigInt mask) =>
      permissions & mask != none;

  static BigInt add(BigInt permissions, BigInt mask) => permissions | mask;

  /// Clears every bit of [mask]. Expressed as `a ^ (a & b)` rather than
  /// `a & ~b` so no intermediate ever becomes a negative BigInt.
  static BigInt remove(BigInt permissions, BigInt mask) =>
      permissions ^ (permissions & mask);

  static BigInt combine(Iterable<BigInt> masks) =>
      masks.fold(none, (result, mask) => result | mask);
}
