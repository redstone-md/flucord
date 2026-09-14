import '../../domain/chat_models.dart';
import '../../domain/read_state.dart';

/// Translates between Discord's read-state wire shapes and the domain models.
///
/// Two dialects have to be read here, not one. R03/R04: a `read_state_type` of
/// 0 spells its cursor `last_message_id` and its badge `mention_count`, while
/// every other type spells the same two fields `last_acked_id` and
/// `badge_count`. Reading a non-channel entry with the channel field names
/// yields a read state that is silently always unread, so the dialect is keyed
/// off the type before any field is touched.
abstract final class DiscordReadStateCodec {
  /// One `READY.read_state.entries[]` element, or `null` when the entry names
  /// no id or a read-state type this build does not model.
  static ReadState? readState(Map<String, Object?> entry) {
    final id = entry['id'];
    if (id is! String || id.isEmpty) return null;
    final type = ReadStateType.fromWire(entry['read_state_type']);
    if (type == null) return null;
    final isChannel = type == ReadStateType.channel;
    return ReadState(
      entityId: id,
      type: type,
      lastAckedId: _snowflake(
        entry[isChannel ? 'last_message_id' : 'last_acked_id'],
      ),
      mentionCount: _count(entry[isChannel ? 'mention_count' : 'badge_count']),
      flags: _int(entry['flags']) ?? 0,
      lastViewed: _int(entry['last_viewed']),
      lastPinTimestamp: _timestamp(entry['last_pin_timestamp']),
    );
  }

  /// One `user_guild_settings.entries[]` element.
  ///
  /// A null `guild_id` is Discord's DM pseudo-guild, which every route
  /// addresses as `@me`; filing it under that key is what lets a DM's settings
  /// be looked up by the same space id the rest of the client already uses.
  static GuildNotificationSettings guildSettings(Map<String, Object?> entry) {
    final guildId = entry['guild_id'];
    return GuildNotificationSettings(
      spaceId: guildId is String && guildId.isNotEmpty
          ? guildId
          : CommunitySpace.directMessagesId,
      muted: entry['muted'] == true,
      muteConfig: muteConfig(entry['mute_config']),
      messageNotifications: MessageNotificationLevel.fromWire(
        entry['message_notifications'],
        orElse: MessageNotificationLevel.allMessages,
      ),
      suppressEveryone: entry['suppress_everyone'] == true,
      suppressRoles: entry['suppress_roles'] == true,
      muteScheduledEvents: entry['mute_scheduled_events'] == true,
      // Discord's default is true, so an absent key must not read as false.
      mobilePush: entry['mobile_push'] != false,
      notifyHighlights: NotifyHighlights.fromWire(entry['notify_highlights']),
      hideMutedChannels: entry['hide_muted_channels'] == true,
      flags: _int(entry['flags']) ?? 0,
      channelOverrides: channelOverrides(entry['channel_overrides']),
      version: _int(entry['version']) ?? -1,
    );
  }

  /// `channel_overrides` arrives as an array carrying `channel_id` on each
  /// entry and is re-keyed by it; a map is accepted too because that is the
  /// shape the client sends back and the shape a cache round trip produces.
  static Map<String, ChannelNotificationOverride> channelOverrides(
    Object? value,
  ) {
    final overrides = <String, ChannelNotificationOverride>{};
    if (value is List) {
      for (final item in value.whereType<Map>()) {
        final entry = item.cast<String, Object?>();
        final id = entry['channel_id'];
        if (id is! String || id.isEmpty) continue;
        overrides[id] = channelOverride(id, entry);
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        final id = entry.key;
        final body = entry.value;
        if (id is! String || id.isEmpty || body is! Map) continue;
        overrides[id] = channelOverride(id, body.cast<String, Object?>());
      }
    }
    return overrides;
  }

  static ChannelNotificationOverride channelOverride(
    String channelId,
    Map<String, Object?> entry,
  ) => ChannelNotificationOverride(
    channelId: channelId,
    muted: entry['muted'] == true,
    muteConfig: muteConfig(entry['mute_config']),
    messageNotifications: MessageNotificationLevel.fromWire(
      entry['message_notifications'],
      orElse: MessageNotificationLevel.inherit,
    ),
    flags: _int(entry['flags']) ?? 0,
    collapsed: entry['collapsed'] == true,
  );

  static NotificationMuteConfig? muteConfig(Object? value) {
    if (value is! Map) return null;
    final entry = value.cast<String, Object?>();
    final endTime = entry['end_time'];
    return NotificationMuteConfig(
      selectedTimeWindowSeconds:
          _int(entry['selected_time_window']) ??
          NotificationMuteConfig.alwaysWindow,
      endTime: endTime is String ? DateTime.tryParse(endTime) : null,
    );
  }

  /// The JSON body a settings PATCH carries for [patch].
  static Map<String, Object?> guildSettingsBody(
    GuildNotificationSettingsPatch patch,
  ) => {
    if (patch.muted != null) 'muted': patch.muted,
    if (patch.clearMuteConfig)
      'mute_config': null
    else if (patch.muteConfig != null)
      'mute_config': muteConfigBody(patch.muteConfig!),
    if (patch.messageNotifications != null)
      'message_notifications': patch.messageNotifications!.wireValue,
    if (patch.suppressEveryone != null)
      'suppress_everyone': patch.suppressEveryone,
    if (patch.suppressRoles != null) 'suppress_roles': patch.suppressRoles,
    if (patch.muteScheduledEvents != null)
      'mute_scheduled_events': patch.muteScheduledEvents,
    if (patch.mobilePush != null) 'mobile_push': patch.mobilePush,
    if (patch.notifyHighlights != null)
      'notify_highlights': patch.notifyHighlights!.wireValue,
    if (patch.flags != null) 'flags': patch.flags,
  };

  static Map<String, Object?> channelOverrideBody(
    ChannelNotificationOverridePatch patch,
  ) => {
    if (patch.muted != null) 'muted': patch.muted,
    if (patch.clearMuteConfig)
      'mute_config': null
    else if (patch.muteConfig != null)
      'mute_config': muteConfigBody(patch.muteConfig!),
    if (patch.messageNotifications != null)
      'message_notifications': patch.messageNotifications!.wireValue,
    if (patch.flags != null) 'flags': patch.flags,
    if (patch.collapsed != null) 'collapsed': patch.collapsed,
  };

  static Map<String, Object?> muteConfigBody(NotificationMuteConfig config) => {
    'selected_time_window': config.selectedTimeWindowSeconds,
    'end_time': config.endTime?.toUtc().toIso8601String(),
  };

  /// Applies [patch] to [settings] the way the server will, so the optimistic
  /// local value and the value that comes back agree.
  static GuildNotificationSettings applyGuildPatch(
    GuildNotificationSettings settings,
    GuildNotificationSettingsPatch patch,
  ) => settings.copyWith(
    muted: patch.muted,
    muteConfig: patch.clearMuteConfig
        ? null
        : patch.muteConfig ?? settings.muteConfig,
    messageNotifications: patch.messageNotifications,
    suppressEveryone: patch.suppressEveryone,
    suppressRoles: patch.suppressRoles,
    muteScheduledEvents: patch.muteScheduledEvents,
    mobilePush: patch.mobilePush,
    notifyHighlights: patch.notifyHighlights,
    flags: patch.flags,
  );

  static ChannelNotificationOverride applyOverridePatch(
    ChannelNotificationOverride override,
    ChannelNotificationOverridePatch patch,
  ) => ChannelNotificationOverride(
    channelId: override.channelId,
    muted: patch.muted ?? override.muted,
    muteConfig: patch.clearMuteConfig
        ? null
        : patch.muteConfig ?? override.muteConfig,
    messageNotifications:
        patch.messageNotifications ?? override.messageNotifications,
    flags: patch.flags ?? override.flags,
    collapsed: patch.collapsed ?? override.collapsed,
  );

  static String? _snowflake(Object? value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value is int) return value == 0 ? null : '$value';
    return null;
  }

  static int? _int(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : null;

  static int _count(Object? value) {
    final count = _int(value) ?? 0;
    return count < 0 ? 0 : count;
  }

  static DateTime? _timestamp(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
