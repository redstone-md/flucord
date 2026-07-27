part of 'read_state.dart';

/// How much of a guild or channel should raise a notification (R04
/// `message_notifications`).
enum MessageNotificationLevel {
  allMessages(0),
  onlyMentions(1),
  noMessages(2),

  /// `3 NULL` on the wire: take the answer from the level above.
  inherit(3);

  const MessageNotificationLevel(this.wireValue);

  final int wireValue;

  static MessageNotificationLevel fromWire(
    Object? value, {
    required MessageNotificationLevel orElse,
  }) {
    if (value is! int) return orElse;
    for (final level in values) {
      if (level.wireValue == value) return level;
    }
    return orElse;
  }
}

/// R04 `notify_highlights`.
enum NotifyHighlights {
  unset(0),
  disabled(1),
  enabled(2);

  const NotifyHighlights(this.wireValue);

  final int wireValue;

  static NotifyHighlights fromWire(Object? value) {
    if (value is! int) return unset;
    for (final option in values) {
      if (option.wireValue == value) return option;
    }
    return unset;
  }
}

/// Whether a surface should light up for every message or only for mentions.
///
/// Distinct from [MessageNotificationLevel]: Discord resolves the unread badge
/// from a separate chain of flag bits and only falls back to the notification
/// level when none of them is set.
enum UnreadBadge { allMessages, onlyMentions }

/// Guild-settings flag bits (R04).
abstract final class GuildNotificationFlags {
  static const unreadsAllMessages = 1 << 11;
  static const unreadsOnlyMentions = 1 << 12;
  static const optInChannelsOff = 1 << 13;
  static const optInChannelsOn = 1 << 14;
}

/// Channel-override flag bits (R04). Note that the two `UNREADS_*` bits are
/// *not* the guild's: they sit at 9 and 10 and in the opposite order.
abstract final class ChannelOverrideFlags {
  static const unreadsOnlyMentions = 1 << 9;
  static const unreadsAllMessages = 1 << 10;
  static const favorited = 1 << 11;
  static const optInEnabled = 1 << 12;
  static const newForumThreadsOff = 1 << 13;
  static const newForumThreadsOn = 1 << 14;
}

/// Account-wide notification flags, from `READY.notification_settings.flags`.
abstract final class AccountNotificationFlags {
  static const useNewNotifications = 1 << 4;
  static const mentionOnAllMessages = 1 << 5;
}

/// A temporary mute (R04 `mute_config`).
final class NotificationMuteConfig {
  const NotificationMuteConfig({
    required this.selectedTimeWindowSeconds,
    this.endTime,
  });

  /// `-1` means "until I turn it back on".
  static const alwaysWindow = -1;

  /// The durations Discord's own mute menu offers, in seconds.
  static const presetWindows = [900, 3600, 10800, 28800, 86400, alwaysWindow];

  final int selectedTimeWindowSeconds;

  /// When the mute lapses, or `null` for a mute with no end.
  final DateTime? endTime;

  bool get isPermanent => endTime == null;

  /// Whether the mute is still in force at [now].
  ///
  /// R04: expiry is a client-side timer — Discord never sends an event for it
  /// and never clears `muted` on the server — so every read of a mute has to
  /// be evaluated against the clock rather than trusted.
  bool isActiveAt(DateTime now) {
    final end = endTime;
    return end == null || now.isBefore(end);
  }

  /// The config a "mute for [window] seconds" request should carry.
  static NotificationMuteConfig forWindow(
    int window, {
    required DateTime now,
  }) => NotificationMuteConfig(
    selectedTimeWindowSeconds: window,
    endTime: window <= 0 ? null : now.add(Duration(seconds: window)),
  );
}

/// One channel's overrides inside a guild's notification settings.
final class ChannelNotificationOverride {
  const ChannelNotificationOverride({
    required this.channelId,
    this.muted = false,
    this.muteConfig,
    this.messageNotifications = MessageNotificationLevel.inherit,
    this.flags = 0,
    this.collapsed = false,
  });

  final String channelId;
  final bool muted;
  final NotificationMuteConfig? muteConfig;
  final MessageNotificationLevel messageNotifications;
  final int flags;
  final bool collapsed;

  bool isMutedAt(DateTime now) =>
      muted && (muteConfig?.isActiveAt(now) ?? true);

  /// The unread badge these flags name, or `null` when they name none.
  UnreadBadge? get unreadBadge {
    if (flags & ChannelOverrideFlags.unreadsAllMessages != 0) {
      return UnreadBadge.allMessages;
    }
    if (flags & ChannelOverrideFlags.unreadsOnlyMentions != 0) {
      return UnreadBadge.onlyMentions;
    }
    return null;
  }
}

/// One guild's notification settings, or the account's DM settings when
/// [spaceId] is the DM pseudo-guild.
final class GuildNotificationSettings {
  GuildNotificationSettings({
    required this.spaceId,
    this.muted = false,
    this.muteConfig,
    this.messageNotifications = MessageNotificationLevel.allMessages,
    this.suppressEveryone = false,
    this.suppressRoles = false,
    this.muteScheduledEvents = false,
    this.mobilePush = true,
    this.notifyHighlights = NotifyHighlights.unset,
    this.hideMutedChannels = false,
    this.flags = 0,
    Map<String, ChannelNotificationOverride> channelOverrides = const {},
    this.version = -1,
  }) : channelOverrides = Map.unmodifiable(channelOverrides);

  /// The defaults Discord's own store starts a guild from, so a guild the
  /// account has never touched answers the same questions as one it has.
  GuildNotificationSettings.defaults(String spaceId) : this(spaceId: spaceId);

  /// The guild id, or [CommunitySpace.directMessagesId] for direct messages.
  final String spaceId;
  final bool muted;
  final NotificationMuteConfig? muteConfig;
  final MessageNotificationLevel messageNotifications;
  final bool suppressEveryone;
  final bool suppressRoles;
  final bool muteScheduledEvents;
  final bool mobilePush;
  final NotifyHighlights notifyHighlights;
  final bool hideMutedChannels;
  final int flags;
  final Map<String, ChannelNotificationOverride> channelOverrides;
  final int version;

  bool get isDirectMessages => spaceId == CommunitySpace.directMessagesId;

  bool isMutedAt(DateTime now) =>
      muted && (muteConfig?.isActiveAt(now) ?? true);

  ChannelNotificationOverride? overrideFor(String? channelId) =>
      channelId == null ? null : channelOverrides[channelId];

  UnreadBadge? get unreadBadge {
    if (flags & GuildNotificationFlags.unreadsAllMessages != 0) {
      return UnreadBadge.allMessages;
    }
    if (flags & GuildNotificationFlags.unreadsOnlyMentions != 0) {
      return UnreadBadge.onlyMentions;
    }
    return null;
  }

  GuildNotificationSettings copyWith({
    bool? muted,
    Object? muteConfig = _keepMuteConfig,
    MessageNotificationLevel? messageNotifications,
    bool? suppressEveryone,
    bool? suppressRoles,
    bool? muteScheduledEvents,
    bool? mobilePush,
    NotifyHighlights? notifyHighlights,
    bool? hideMutedChannels,
    int? flags,
    Map<String, ChannelNotificationOverride>? channelOverrides,
    int? version,
  }) => GuildNotificationSettings(
    spaceId: spaceId,
    muted: muted ?? this.muted,
    muteConfig: identical(muteConfig, _keepMuteConfig)
        ? this.muteConfig
        : muteConfig as NotificationMuteConfig?,
    messageNotifications: messageNotifications ?? this.messageNotifications,
    suppressEveryone: suppressEveryone ?? this.suppressEveryone,
    suppressRoles: suppressRoles ?? this.suppressRoles,
    muteScheduledEvents: muteScheduledEvents ?? this.muteScheduledEvents,
    mobilePush: mobilePush ?? this.mobilePush,
    notifyHighlights: notifyHighlights ?? this.notifyHighlights,
    hideMutedChannels: hideMutedChannels ?? this.hideMutedChannels,
    flags: flags ?? this.flags,
    channelOverrides: channelOverrides ?? this.channelOverrides,
    version: version ?? this.version,
  );

  /// Replaces one channel's overrides, dropping the entry when [override] is
  /// null so a cleared override does not linger as an all-defaults record.
  GuildNotificationSettings withOverride(
    String channelId,
    ChannelNotificationOverride? override,
  ) {
    final next = {...channelOverrides};
    if (override == null) {
      next.remove(channelId);
    } else {
      next[channelId] = override;
    }
    return copyWith(channelOverrides: next);
  }

  static const _keepMuteConfig = Object();
}

/// The leaves a caller wants changed on a guild's settings.
///
/// Discord merges a settings PATCH field by field, so naming only what changed
/// is both the smallest correct request and the one that cannot clobber a
/// field this client does not model.
final class GuildNotificationSettingsPatch {
  const GuildNotificationSettingsPatch({
    this.muted,
    this.muteConfig,
    this.clearMuteConfig = false,
    this.messageNotifications,
    this.suppressEveryone,
    this.suppressRoles,
    this.muteScheduledEvents,
    this.mobilePush,
    this.notifyHighlights,
    this.flags,
  });

  final bool? muted;
  final NotificationMuteConfig? muteConfig;
  final bool clearMuteConfig;
  final MessageNotificationLevel? messageNotifications;
  final bool? suppressEveryone;
  final bool? suppressRoles;
  final bool? muteScheduledEvents;
  final bool? mobilePush;
  final NotifyHighlights? notifyHighlights;
  final int? flags;

  // `hide_muted_channels` is deliberately absent. R04 lists it as a field this
  // client only ever saw toggled locally, never sent, so writing it would be
  // inventing wire behaviour rather than reproducing it.

  bool get isEmpty =>
      muted == null &&
      muteConfig == null &&
      !clearMuteConfig &&
      messageNotifications == null &&
      suppressEveryone == null &&
      suppressRoles == null &&
      muteScheduledEvents == null &&
      mobilePush == null &&
      notifyHighlights == null &&
      flags == null;
}

/// The leaves a caller wants changed on one channel's override.
final class ChannelNotificationOverridePatch {
  const ChannelNotificationOverridePatch({
    this.muted,
    this.muteConfig,
    this.clearMuteConfig = false,
    this.messageNotifications,
    this.flags,
    this.collapsed,
  });

  final bool? muted;
  final NotificationMuteConfig? muteConfig;
  final bool clearMuteConfig;
  final MessageNotificationLevel? messageNotifications;
  final int? flags;
  final bool? collapsed;

  bool get isEmpty =>
      muted == null &&
      muteConfig == null &&
      !clearMuteConfig &&
      messageNotifications == null &&
      flags == null &&
      collapsed == null;
}
