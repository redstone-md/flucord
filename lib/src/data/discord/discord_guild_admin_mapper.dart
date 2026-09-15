import '../../domain/chat_models.dart';
import '../../domain/discord_permissions.dart';
import '../../domain/guild_audit_log.dart';
import '../../domain/guild_management.dart';
import 'discord_cdn.dart';
import 'discord_mapper.dart';
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

  /// The member record the member popover moderates from.
  ///
  /// Roles and timeout are what the moderation actions read; the user record
  /// beside them is not, so it is not read here.
  static GuildMemberProfile memberProfile(
    Map<String, Object?> payload, {
    required String guildId,
    required String userId,
  }) => GuildMemberProfile(
    userId: userId,
    guildId: guildId,
    roleIds: _ids(payload['roles']),
    nickname: _string(payload['nick']),
    timeoutUntil: _timestamp(payload['communication_disabled_until']),
  );

  static DateTime? _timestamp(Object? value) {
    final raw = _string(value);
    return raw == null ? null : DateTime.tryParse(raw);
  }

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

  /// Reads a webhook payload, or null when it has no id. The token is dropped
  /// on purpose: this client posts nothing as a webhook, so carrying a
  /// credential it never uses only widens what a copy-paste leaks.
  static GuildWebhook? webhook(Map<String, Object?> payload, String guildId) {
    final id = _string(payload['id']);
    if (id == null) return null;
    return GuildWebhook(
      id: id,
      guildId: _string(payload['guild_id']) ?? guildId,
      channelId: _string(payload['channel_id']) ?? '',
      name: _string(payload['name']) ?? 'unnamed',
      type:
          GuildWebhookType.fromWire(payload['type']) ??
          GuildWebhookType.incoming,
    );
  }

  static List<GuildWebhook> webhooks(
    List<Map<String, Object?>> payloads,
    String guildId,
  ) => [
    for (final payload in payloads)
      if (webhook(payload, guildId) case final GuildWebhook value) value,
  ];

  /// The preview `GET /invites/{code}` answers with.
  ///
  /// The guild rides nested, and its icon hash becomes the URL the join
  /// surface draws. Counts arrive only when the request asked for them, so
  /// they stay optional here exactly as they are on the wire.
  static InvitePreview? invitePreview(Map<String, Object?> payload) {
    final code = _string(payload['code']);
    final guild = payload['guild'];
    if (code == null || guild is! Map) return null;
    final guildPayload = guild.cast<String, Object?>();
    final id = _string(guildPayload['id']);
    final name = _string(guildPayload['name']);
    if (id == null || name == null) return null;
    final channel = payload['channel'];
    final banner = _string(guildPayload['banner']);
    return InvitePreview(
      code: code,
      name: name,
      guildId: id,
      description: _string(guildPayload['description']),
      iconUrl: DiscordCdn.guildIcon(id, _string(guildPayload['icon'])),
      bannerUrl: banner == null ? null : DiscordCdn.guildBanner(id, banner),
      channelName: channel is Map ? _string(channel['name']) : null,
      approximateMemberCount: _int(payload['approximate_member_count']),
    );
  }

  /// A hydration answer, from the guild object plus the routes that fill it.
  ///
  /// [channels] and [roles] come from `GET /guilds/{id}/channels` and
  /// `GET /guilds/{id}/roles`; [members] is this account's own membership,
  /// which the desktop session is told without a member walk. The space is
  /// read from the guild object with the same projection READY uses, so a
  /// joined server draws exactly like one the session was opened with.
  static JoinedGuild joinedGuild({
    required Map<String, Object?> guild,
    required List<Map<String, Object?>> channels,
    required List<Map<String, Object?>> roles,
    required DiscordMapper mapper,
    List<Member> members = const [],
  }) {
    final guildId = _string(guild['id']) ?? '';
    return JoinedGuild(
      space: mapper.spaceFromGuildPayload(guild),
      channels: [
        for (final payload in channels) ?mapper.channel(payload, guildId),
      ],
      categories: [
        for (final payload in channels) ?mapper.category(payload, guildId),
      ],
      roles: [for (final payload in roles) mapper.role(payload, guildId)],
      members: members,
    );
  }

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

/// The guild id a join or create answer names.
///
/// The join POST answers a partial guild whose `id` is the guild; the create
/// POST answers a full guild object with the same field. One reader for both
/// keeps a change in either shape a change in one place.
String guildIdOfInvite(Map<String, Object?> payload) {
  final id = payload['id'];
  if (id is String && id.isNotEmpty) return id;
  final guild = payload['guild'];
  if (guild is Map) {
    final guildId = guild['id'];
    if (guildId is String && guildId.isNotEmpty) return guildId;
  }
  return '';
}
