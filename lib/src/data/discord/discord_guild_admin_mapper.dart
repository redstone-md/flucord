import '../../domain/discord_permissions.dart';
import '../../domain/guild_audit_log.dart';
import '../../domain/guild_management.dart';
import 'discord_snowflake.dart';

/// Reads the guild-administration payloads into domain records.
///
/// Every field here is optional on the way in even when Discord always sends
/// it. A settings window that threw on one missing key would take the whole
/// guild down over a field it does not render, and Discord adds and retires
/// fields on these routes without notice.
abstract final class DiscordGuildAdminMapper {
  static GuildOverviewSettings guildOverview(Map<String, Object?> payload) =>
      GuildOverviewSettings(
        id: _string(payload['id']) ?? '',
        name: _string(payload['name']) ?? '',
        iconHash: _string(payload['icon']),
        description: _string(payload['description']),
        ownerId: _string(payload['owner_id']),
        preferredLocale: _string(payload['preferred_locale']),
        afkChannelId: _string(payload['afk_channel_id']),
        afkTimeoutSeconds: _int(payload['afk_timeout']) ?? 300,
        systemChannelId: _string(payload['system_channel_id']),
        systemChannelFlags: _int(payload['system_channel_flags']) ?? 0,
        verificationLevel: GuildVerificationLevel.fromWire(
          payload['verification_level'],
        ),
        explicitContentFilter: GuildExplicitContentFilter.fromWire(
          payload['explicit_content_filter'],
        ),
        defaultMessageNotifications: GuildNotificationLevel.fromWire(
          payload['default_message_notifications'],
        ),
        mfaLevel: GuildMfaLevel.fromWire(payload['mfa_level']),
        premiumProgressBarEnabled:
            payload['premium_progress_bar_enabled'] == true,
        features: {
          for (final feature in _list(payload['features']))
            if (feature is String) feature,
        },
      );

  static GuildRole role(Map<String, Object?> payload, String guildId) {
    final colors = payload['colors'];
    final primary = colors is Map ? _int(colors['primary_color']) : null;
    return GuildRole(
      id: _string(payload['id']) ?? '',
      guildId: guildId,
      name: _string(payload['name']) ?? '',
      position: _int(payload['position']) ?? 0,
      // `parse`, not `tryParse`: a bitfield this client cannot read must grant
      // nothing. The one time a client got this wrong, a "-1" permission string
      // read back as every bit set and handed out administrator.
      permissions: DiscordPermissions.parse(payload['permissions']),
      colorValue: primary ?? _int(payload['color']) ?? 0,
      hoist: payload['hoist'] == true,
      mentionable: payload['mentionable'] == true,
      managed: payload['managed'] == true,
      iconHash: _string(payload['icon']),
      unicodeEmoji: _string(payload['unicode_emoji']),
    );
  }

  static List<GuildRole> roles(
    List<Map<String, Object?>> payloads,
    String guildId,
  ) => [for (final payload in payloads) role(payload, guildId)];

  static GuildBan? ban(Map<String, Object?> payload) {
    final user = payload['user'];
    if (user is! Map) return null;
    final id = _string(user['id']);
    if (id == null) return null;
    return GuildBan(
      userId: id,
      userName: _string(user['username']) ?? id,
      globalName: _string(user['global_name']),
      avatarHash: _string(user['avatar']),
      reason: _string(payload['reason']),
    );
  }

  static List<GuildBan> bans(List<Map<String, Object?>> payloads) => [
    for (final payload in payloads)
      if (ban(payload) case final GuildBan value) value,
  ];

  static BulkBanResult bulkBanResult(Map<String, Object?> payload) =>
      BulkBanResult(
        bannedUserIds: _ids(payload['banned_users']),
        failedUserIds: _ids(payload['failed_users']),
      );

  static GuildInvite? invite(Map<String, Object?> payload) {
    final code = _string(payload['code']);
    if (code == null) return null;
    final channel = payload['channel'];
    final inviter = payload['inviter'];
    final createdAt = _string(payload['created_at']);
    return GuildInvite(
      code: code,
      channelId: channel is Map
          ? _string(channel['id'])
          : _string(payload['channel_id']),
      channelName: channel is Map ? _string(channel['name']) : null,
      inviterId: inviter is Map ? _string(inviter['id']) : null,
      inviterName: inviter is Map
          ? _string(inviter['global_name']) ?? _string(inviter['username'])
          : null,
      uses: _int(payload['uses']) ?? 0,
      maxUses: _int(payload['max_uses']) ?? 0,
      maxAgeSeconds: _int(payload['max_age']) ?? 0,
      temporary: payload['temporary'] == true,
      createdAt: createdAt == null ? null : DateTime.tryParse(createdAt),
    );
  }

  static List<GuildInvite> invites(List<Map<String, Object?>> payloads) => [
    for (final payload in payloads)
      if (invite(payload) case final GuildInvite value) value,
  ];

  static AuditLogPage auditLog(Map<String, Object?> payload) {
    final entries = <AuditLogEntry>[];
    for (final raw in _list(payload['audit_log_entries'])) {
      if (raw is! Map) continue;
      final entry = auditLogEntry(raw.cast<String, Object?>());
      if (entry != null) entries.add(entry);
    }
    return AuditLogPage(
      entries: List.unmodifiable(entries),
      userNames: _names(payload['users']),
      channelNames: _names(payload['threads']),
    );
  }

  static AuditLogEntry? auditLogEntry(Map<String, Object?> payload) {
    final id = _string(payload['id']);
    final action = AuditLogActionType.fromWire(payload['action_type']);
    // An action id this build has no name for is dropped rather than rendered
    // as a blank row: the entry's whole meaning is its action, and a row that
    // says an unnamed thing happened to an unnamed target is noise that pushes
    // real entries off the page.
    if (id == null || action == null) return null;
    final options = payload['options'];
    return AuditLogEntry(
      id: id,
      action: action,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        DiscordSnowflake.timestampMillis(id),
      ),
      targetId: _string(payload['target_id']),
      userId: _string(payload['user_id']),
      reason: _string(payload['reason']),
      changes: [
        for (final raw in _list(payload['changes']))
          if (raw is Map && raw['key'] is String)
            AuditLogChange(
              key: raw['key']! as String,
              oldValue: raw['old_value'],
              newValue: raw['new_value'],
            ),
      ],
      options: options is Map
          ? Map.unmodifiable(options.cast<String, Object?>())
          : const {},
    );
  }

  static Map<String, String> _names(Object? value) {
    final names = <String, String>{};
    for (final raw in _list(value)) {
      if (raw is! Map) continue;
      final id = _string(raw['id']);
      if (id == null) continue;
      names[id] =
          _string(raw['global_name']) ??
          _string(raw['username']) ??
          _string(raw['name']) ??
          id;
    }
    return Map.unmodifiable(names);
  }

  static List<String> _ids(Object? value) => [
    for (final raw in _list(value))
      if (_string(raw) case final String id) id,
  ];

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  static int? _int(Object? value) => switch (value) {
    final int raw => raw,
    final String raw => int.tryParse(raw),
    _ => null,
  };
}
