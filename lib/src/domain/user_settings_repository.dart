import 'chat_models.dart';
import 'user_settings.dart';

/// The settings a caller wants changed, and nothing else.
///
/// Discord merges a settings write by replacing whole top-level groups, so a
/// caller must never hand over a rebuilt settings object: anything it failed
/// to copy would be erased on the account. Naming only the leaves that changed
/// keeps that mistake unavailable — the transport clones the stored group and
/// edits it, so fields Flucord does not model survive the round trip.
final class UserSettingsPatch {
  const UserSettingsPatch({
    this.theme,
    this.timestampHourCycle,
    this.renderEmbeds,
    this.renderReactions,
    this.inlineAttachmentMedia,
    this.inlineEmbedMedia,
    this.spamFilter,
    this.quietMode,
    this.notifyFriendsOnGoLive,
    this.friendOnlineNotifications,
    this.reactionNotifications,
    this.allowActivityPartyFriends,
    this.allowActivityPartyVoiceChannel,
    this.detectPlatformAccounts,
    this.showLocalTime,
    this.hideLegacyUsername,
    this.onlineStatus,
    this.customStatusText,
    this.customStatusEmojiName,
    this.customStatusExpiresAtMs,
    this.clearCustomStatus = false,
    this.showCurrentGame,
  });

  final UserSettingsTheme? theme;
  final TimestampHourCycle? timestampHourCycle;

  final bool? renderEmbeds;
  final bool? renderReactions;
  final bool? inlineAttachmentMedia;
  final bool? inlineEmbedMedia;
  final DirectMessageSpamFilter? spamFilter;

  final bool? quietMode;
  final bool? notifyFriendsOnGoLive;
  final bool? friendOnlineNotifications;
  final ReactionNotifications? reactionNotifications;

  final bool? allowActivityPartyFriends;
  final bool? allowActivityPartyVoiceChannel;
  final bool? detectPlatformAccounts;
  final bool? showLocalTime;
  final bool? hideLegacyUsername;

  /// The status the account should carry between clients.
  ///
  /// Only the four selectable statuses are meaningful here. `streaming` is a
  /// render-time synthesis and `unknown` is what the server writes, so neither
  /// is something a client may store.
  final Presence? onlineStatus;

  final String? customStatusText;

  /// The Unicode emoji beside the custom status, or the empty string to drop
  /// the one already stored.
  final String? customStatusEmojiName;

  /// When the custom status should clear itself, in epoch milliseconds. Zero
  /// is Discord's "never".
  final int? customStatusExpiresAtMs;

  /// Removes the custom status message entirely, which is not the same as
  /// setting its text to the empty string: Discord keeps the emoji and the
  /// expiry on the same submessage.
  final bool clearCustomStatus;
  final bool? showCurrentGame;

  bool get touchesAppearance => theme != null || timestampHourCycle != null;

  bool get touchesTextAndImages =>
      renderEmbeds != null ||
      renderReactions != null ||
      inlineAttachmentMedia != null ||
      inlineEmbedMedia != null ||
      spamFilter != null;

  bool get touchesNotifications =>
      quietMode != null ||
      notifyFriendsOnGoLive != null ||
      friendOnlineNotifications != null ||
      reactionNotifications != null;

  bool get touchesPrivacy =>
      allowActivityPartyFriends != null ||
      allowActivityPartyVoiceChannel != null ||
      detectPlatformAccounts != null ||
      showLocalTime != null ||
      hideLegacyUsername != null;

  bool get touchesStatus =>
      onlineStatus != null ||
      customStatusText != null ||
      customStatusEmojiName != null ||
      customStatusExpiresAtMs != null ||
      clearCustomStatus ||
      showCurrentGame != null;

  bool get isEmpty =>
      !touchesAppearance &&
      !touchesTextAndImages &&
      !touchesNotifications &&
      !touchesPrivacy &&
      !touchesStatus;
}

/// How urgently a change should reach Discord.
///
/// R06's save-delay tiers, in the two flavours a settings screen needs: a
/// deliberate click goes out at once, while something the client decides on
/// the user's behalf waits with the rest of the batch.
enum UserSettingsSaveDelay {
  immediate(Duration.zero),
  batched(Duration(seconds: 30));

  const UserSettingsSaveDelay(this.delay);

  final Duration delay;
}

/// Account-level client settings, as served by `/users/@me/settings-proto`.
///
/// This is server state with a live feed, not a local preference store: the
/// same account edited from another device arrives as a dispatch, and a write
/// is a whole-group replacement the server acknowledges with the merged
/// result. Callers therefore read [current] for what is true now and listen to
/// [updates] for what became true, rather than assuming their own write won.
abstract interface class UserSettingsRepository {
  /// Emits whenever the stored settings change, from any source.
  Stream<UserSettings> get updates;

  /// The settings as last known, or `null` before the first blob arrives.
  UserSettings? get current;

  /// Whether a blob has been decoded, which is what makes writes legal.
  bool get isLoaded;

  /// Why the last write failed, or `null` when the last one succeeded.
  ///
  /// A write leaves on a timer well after the click that caused it, so the
  /// failure cannot come back as a thrown exception from [apply]. It is
  /// reported here and announced on [updates] so a surface showing optimistic
  /// values can admit that Discord never took them.
  Object? get lastWriteError;

  /// Fetches the blob if it has not arrived on the gateway already.
  Future<UserSettings> load();

  /// Applies [patch] optimistically and schedules the write.
  ///
  /// Throws [StateError] when nothing has been loaded yet: without the stored
  /// groups there is nothing to clone, and writing a group built from scratch
  /// would drop every field Flucord does not model.
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  });

  /// Sends any scheduled write now, for shutdown and window-hide paths.
  Future<void> flush();
}
