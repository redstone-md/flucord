/// How far a stored setting actually reaches once Flucord has read it.
///
/// Discord's blob carries preferences for surfaces Flucord has not built, and
/// a switch that moves but changes nothing is worse than no switch at all. The
/// settings surface renders this verdict next to every row so the answer is
/// visible rather than implied.
enum UserSettingSupport {
  /// Flucord reads the value and renders or behaves differently for it.
  applied,

  /// The value is account state: Flucord stores what the user chooses and
  /// hands it back to Discord, but nothing in Flucord reacts to it.
  accountOnly,

  /// Flucord has no surface this setting could change. Shown read-only.
  unavailable,
}

/// `AppearanceSettings.theme`, as R06 numbers it.
enum UserSettingsTheme {
  unset(0),
  dark(1),
  light(2),
  darker(3),
  midnight(4);

  const UserSettingsTheme(this.wireValue);

  final int wireValue;

  static UserSettingsTheme fromWire(int? value) => switch (value) {
    1 => dark,
    2 => light,
    3 => darker,
    4 => midnight,
    _ => unset,
  };

  /// Whether Flucord can render this theme.
  ///
  /// Flucord ships one dark and one light palette. Darker and Midnight are
  /// distinct palettes in Discord, so offering them here would be a promise
  /// the renderer cannot keep.
  bool get isRenderable => this == dark || this == light;
}

/// `AppearanceSettings.timestamp_hour_cycle`.
enum TimestampHourCycle {
  auto(0),
  hour12(1),
  hour23(2);

  const TimestampHourCycle(this.wireValue);

  final int wireValue;

  static TimestampHourCycle fromWire(int? value) => switch (value) {
    1 => hour12,
    2 => hour23,
    _ => auto,
  };
}

/// `AppearanceSettings.ui_density`.
enum UserInterfaceDensity {
  unset(0),
  compact(1),
  cozy(2),
  responsive(3),
  standard(4);

  const UserInterfaceDensity(this.wireValue);

  final int wireValue;

  static UserInterfaceDensity fromWire(int? value) => switch (value) {
    1 => compact,
    2 => cozy,
    3 => responsive,
    4 => standard,
    _ => unset,
  };
}

/// `TextAndImagesSettings.dm_spam_filter_v2`.
enum DirectMessageSpamFilter {
  defaultUnset(0),
  disabled(1),
  nonFriends(2),
  friendsAndNonFriends(3);

  const DirectMessageSpamFilter(this.wireValue);

  final int wireValue;

  static DirectMessageSpamFilter fromWire(int? value) => switch (value) {
    1 => disabled,
    2 => nonFriends,
    3 => friendsAndNonFriends,
    _ => defaultUnset,
  };
}

/// `NotificationSettings.reaction_notifications`.
enum ReactionNotifications {
  enabled(0),
  onlyDirectMessages(1),
  disabled(2);

  const ReactionNotifications(this.wireValue);

  final int wireValue;

  static ReactionNotifications fromWire(int? value) => switch (value) {
    1 => onlyDirectMessages,
    2 => disabled,
    _ => enabled,
  };
}

/// `PreloadedUserSettings.appearance`.
final class AppearancePreferences {
  const AppearancePreferences({
    this.theme = UserSettingsTheme.unset,
    this.developerMode = false,
    this.density = UserInterfaceDensity.unset,
    this.timestampHourCycle = TimestampHourCycle.auto,
    this.darkSidebar = false,
  });

  final UserSettingsTheme theme;
  final bool developerMode;
  final UserInterfaceDensity density;
  final TimestampHourCycle timestampHourCycle;
  final bool darkSidebar;
}

/// The `PreloadedUserSettings.text_and_images` leaves that describe a message.
///
/// Every field is nullable because the wire type is a presence-tracking
/// wrapper: "the user turned embeds off" and "the account has never expressed
/// an opinion" are different states, and only the second may fall back to a
/// Flucord default.
final class MessageDisplayPreferences {
  const MessageDisplayPreferences({
    this.renderEmbeds,
    this.renderReactions,
    this.inlineAttachmentMedia,
    this.inlineEmbedMedia,
    this.gifAutoPlay,
    this.animateEmoji,
    this.compact,
    this.convertEmoticons,
    this.enableTextToSpeechCommand,
    this.showCommandSuggestions,
    this.spamFilter = DirectMessageSpamFilter.defaultUnset,
  });

  final bool? renderEmbeds;
  final bool? renderReactions;
  final bool? inlineAttachmentMedia;
  final bool? inlineEmbedMedia;
  final bool? gifAutoPlay;
  final bool? animateEmoji;
  final bool? compact;
  final bool? convertEmoticons;
  final bool? enableTextToSpeechCommand;
  final bool? showCommandSuggestions;
  final DirectMessageSpamFilter spamFilter;

  /// R06 records no client default for the four rendering wrappers below, so
  /// these fallbacks are Flucord's own: an account that never touched the
  /// setting sees everything, which is what the client did before it could
  /// read settings at all.
  bool get rendersEmbeds => renderEmbeds ?? true;
  bool get rendersReactions => renderReactions ?? true;
  bool get rendersAttachmentMedia => inlineAttachmentMedia ?? true;
  bool get rendersEmbedMedia => inlineEmbedMedia ?? true;

  /// R06 does record this one: the renderer's accessor defaults it to false.
  bool get isCompact => compact ?? false;
}

/// `PreloadedUserSettings.notifications`.
final class NotificationPreferences {
  const NotificationPreferences({
    this.quietMode,
    this.showInAppNotifications,
    this.notifyFriendsOnGoLive,
    this.friendOnlineNotifications,
    this.reactionNotifications = ReactionNotifications.enabled,
  });

  final bool? quietMode;
  final bool? showInAppNotifications;
  final bool? notifyFriendsOnGoLive;
  final bool? friendOnlineNotifications;
  final ReactionNotifications reactionNotifications;

  /// R06: every notification toggle defaults to true except quiet mode.
  bool get isQuiet => quietMode ?? false;
  bool get showsInAppNotifications => showInAppNotifications ?? true;
  bool get notifiesFriendsOnGoLive => notifyFriendsOnGoLive ?? true;
  bool get notifiesOnFriendOnline => friendOnlineNotifications ?? true;
}

/// `PreloadedUserSettings.privacy`.
final class PrivacyPreferences {
  const PrivacyPreferences({
    this.allowActivityPartyFriends,
    this.allowActivityPartyVoiceChannel,
    this.defaultGuildsRestricted = false,
    this.detectPlatformAccounts,
    this.showLocalTime,
    this.hideLegacyUsername,
  });

  final bool? allowActivityPartyFriends;
  final bool? allowActivityPartyVoiceChannel;
  final bool defaultGuildsRestricted;
  final bool? detectPlatformAccounts;
  final bool? showLocalTime;
  final bool? hideLegacyUsername;

  /// R06 gives true for both activity-party flags and false for the legacy
  /// username toggle. It gives nothing for platform-account detection or local
  /// time, so those two fall back to false — the quieter answer for a setting
  /// whose meaning is to share something.
  bool get allowsActivityPartyFriends => allowActivityPartyFriends ?? true;
  bool get allowsActivityPartyVoiceChannel =>
      allowActivityPartyVoiceChannel ?? true;
  bool get detectsPlatformAccounts => detectPlatformAccounts ?? false;
  bool get showsLocalTime => showLocalTime ?? false;
  bool get hidesLegacyUsername => hideLegacyUsername ?? false;
}

/// `PreloadedUserSettings.localization`.
final class LocalizationPreferences {
  const LocalizationPreferences({
    this.locale,
    this.timezoneName,
    this.timezoneOffsetMinutes,
  });

  final String? locale;
  final String? timezoneName;
  final int? timezoneOffsetMinutes;
}

/// `PreloadedUserSettings.status`.
final class StatusPreferences {
  const StatusPreferences({
    this.status,
    this.customStatusText,
    this.customStatusEmojiName,
    this.customStatusEmojiId,
    this.customStatusExpiresAtMs = 0,
    this.showCurrentGame,
    this.statusExpiresAtMs = 0,
  });

  final String? status;
  final String? customStatusText;
  final String? customStatusEmojiName;

  /// The snowflake of a custom guild emoji, or null for a Unicode one.
  final String? customStatusEmojiId;
  final int customStatusExpiresAtMs;
  final bool? showCurrentGame;
  final int statusExpiresAtMs;

  /// R06: `status.showCurrentGame` defaults to true.
  bool get showsCurrentGame => showCurrentGame ?? true;
  bool get hasCustomStatus =>
      (customStatusText?.isNotEmpty ?? false) ||
      (customStatusEmojiName?.isNotEmpty ?? false);
}

/// The one `PreloadedUserSettings.voice_and_video` leaf presence depends on.
final class VoiceAndVideoPreferences {
  const VoiceAndVideoPreferences({this.afkTimeoutSeconds});

  final int? afkTimeoutSeconds;

  /// R06 gives 60 as the proto default, and R07 multiplies it by one second.
  ///
  /// Zero is a real value that means "always AFK", so it is passed through
  /// rather than folded into the default.
  int get afkTimeout => afkTimeoutSeconds ?? 60;
}

/// The account-level settings Flucord models, as of the last blob it saw.
final class UserSettings {
  const UserSettings({
    this.appearance = const AppearancePreferences(),
    this.messageDisplay = const MessageDisplayPreferences(),
    this.notifications = const NotificationPreferences(),
    this.privacy = const PrivacyPreferences(),
    this.localization = const LocalizationPreferences(),
    this.status = const StatusPreferences(),
    this.voiceAndVideo = const VoiceAndVideoPreferences(),
    this.dataVersion = 0,
  });

  final AppearancePreferences appearance;
  final MessageDisplayPreferences messageDisplay;
  final NotificationPreferences notifications;
  final PrivacyPreferences privacy;
  final LocalizationPreferences localization;
  final StatusPreferences status;
  final VoiceAndVideoPreferences voiceAndVideo;

  /// `Versions.data_version`, the server's counter for this blob.
  final int dataVersion;
}
