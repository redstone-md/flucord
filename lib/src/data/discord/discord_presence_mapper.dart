import '../../domain/chat_models.dart';
import 'discord_cdn.dart';

/// One presence exactly as the gateway reported it, scope included.
///
/// The scope has to survive mapping because Discord sends the same user's
/// presence once per subscribed guild plus once for the friend list, and only
/// the store that holds all of them can decide which one is current.
final class DiscordPresenceRecord {
  const DiscordPresenceRecord({
    required this.userId,
    required this.presence,
    this.guildId,
    this.processedAtTimestamp = 0,
    this.user,
  });

  final String userId;

  /// The guild this presence was reported for, or null for friend/DM scope.
  final String? guildId;

  /// Discord's own ordering key. Presences for one user arrive out of order
  /// across guilds, and this is the only field that says which is newest.
  final int processedAtTimestamp;

  final UserPresence presence;

  /// The user object the presence carried, when it carried more than an id.
  final Map<String, Object?>? user;
}

/// Turns raw presence, activity and session payloads into domain values.
abstract final class DiscordPresenceMapper {
  /// Upper bound on how many activities one presence may contribute.
  ///
  /// Discord's own local list tops out at six entries and the UI shows one, so
  /// this is far above anything legitimate. It exists because the array length
  /// is wire-supplied and would otherwise size an allocation directly.
  static const maxActivities = 32;

  /// R07's RPC write validator caps buttons at two; the read path is bounded
  /// to the same number rather than trusting the array it is handed.
  static const maxButtons = 2;

  /// Same reasoning, for `supported_platforms`.
  static const maxSupportedPlatforms = 10;

  /// Longest string this client will keep out of an activity.
  ///
  /// R07's write limits are 128 characters for every text leaf. Doubling that
  /// leaves room for a server that is more generous than its own validator
  /// while still refusing to hand a megabyte of text to a text painter.
  static const maxTextLength = 256;

  /// Maps one presence object. Returns null when it names no user.
  static DiscordPresenceRecord? record(
    Map<String, Object?> payload, {
    String? guildId,
  }) {
    final user = payload['user'];
    final userId = user is Map
        ? user['id'] as String?
        : payload['user_id'] as String?;
    if (userId == null || userId.isEmpty) return null;
    final activities = _activities(payload['activities']);
    return DiscordPresenceRecord(
      userId: userId,
      // A presence's own `guild_id` wins over the scope it was found in: a
      // GUILD_CREATE snapshot names its guild on the outside, but a batched
      // PRESENCE_UPDATE carries it on the payload itself.
      guildId: payload['guild_id'] as String? ?? guildId,
      processedAtTimestamp: _int(payload['processed_at_timestamp']) ?? 0,
      user: user is Map ? user.cast<String, Object?>() : null,
      presence: UserPresence(
        status: Presence.fromWire(payload['status']),
        clientStatus: clientStatus(payload['client_status']),
        activities: activities,
        hiddenActivities: _activities(payload['hidden_activities']),
      ),
    );
  }

  /// Maps a `presences` array, dropping entries that name no user.
  static List<DiscordPresenceRecord> records(
    Object? payload, {
    String? guildId,
  }) {
    if (payload is! List) return const [];
    final mapped = <DiscordPresenceRecord>[];
    for (final entry in payload.whereType<Map>()) {
      final result = record(entry.cast<String, Object?>(), guildId: guildId);
      if (result != null) mapped.add(result);
    }
    return mapped;
  }

  /// Maps `client_status`. Unrecognised keys fold into [ClientPlatform.unknown]
  /// so that a device Discord adds later still counts as somewhere online.
  static Map<ClientPlatform, Presence> clientStatus(Object? payload) {
    if (payload is! Map) return const {};
    final result = <ClientPlatform, Presence>{};
    for (final entry in payload.entries) {
      final key = entry.key;
      if (key is! String) continue;
      result[ClientPlatform.fromWire(key)] = Presence.fromWire(entry.value);
    }
    return result;
  }

  /// Maps one activity. Returns null without a usable `name`, which R07 marks
  /// as the schema's only required field.
  static UserActivity? activity(Map<String, Object?> payload) {
    final name = _text(payload['name']);
    if (name == null || name.isEmpty) return null;
    final type = ActivityType.fromWire(payload['type']);
    final createdAt = _int(payload['created_at']);
    final applicationId = _text(payload['application_id']);
    return UserActivity(
      name: name,
      type: type,
      sessionId: _text(payload['session_id']),
      url: _text(payload['url']),
      applicationId: applicationId,
      statusDisplayType: StatusDisplayType.fromWire(
        payload['status_display_type'],
      ),
      state: _text(payload['state']),
      stateUrl: _text(payload['state_url']),
      details: _text(payload['details']),
      detailsUrl: _text(payload['details_url']),
      emoji: _emoji(payload['emoji']),
      assets: _assets(payload['assets'], applicationId),
      timestamps: _timestamps(
        payload['timestamps'],
        type: type,
        createdAtMs: createdAt,
      ),
      party: _party(payload['party']),
      secrets: _secrets(payload['secrets']),
      syncId: _text(payload['sync_id']),
      createdAtMs: createdAt,
      instance: payload['instance'] == true,
      flags: _flags(payload['flags']),
      platform: _text(payload['platform']),
      supportedPlatforms: _strings(
        payload['supported_platforms'],
        maxSupportedPlatforms,
      ),
      buttons: _strings(payload['buttons'], maxButtons),
    );
  }

  /// Maps one session object from `SESSIONS_REPLACE` or `READY.sessions`.
  static UserSession? session(Map<String, Object?> payload) {
    final id = payload['session_id'];
    if (id is! String || id.isEmpty) return null;
    final info = payload['client_info'];
    return UserSession(
      sessionId: id,
      status: Presence.fromWire(payload['status']),
      lastModified: _int(payload['last_modified']) ?? 0,
      activities: _activities(payload['activities']),
      hiddenActivities: _activities(payload['hidden_activities']),
      active: payload['active'] == true,
      operatingSystem: info is Map ? _text(info['os']) : null,
    );
  }

  /// Maps a bare session array. `SESSIONS_REPLACE` dispatches one directly as
  /// its `d`, so the caller may hand this the dispatch payload itself.
  static List<UserSession> sessions(Object? payload) {
    if (payload is! List) return const [];
    final mapped = <UserSession>[];
    for (final entry in payload.whereType<Map>()) {
      final result = session(entry.cast<String, Object?>());
      if (result != null) mapped.add(result);
    }
    return mapped;
  }

  static List<UserActivity> _activities(Object? payload) {
    if (payload is! List) return const [];
    final mapped = <UserActivity>[];
    for (final entry in payload.whereType<Map>()) {
      if (mapped.length == maxActivities) break;
      final result = activity(entry.cast<String, Object?>());
      if (result != null) mapped.add(result);
    }
    return mapped;
  }

  static ActivityEmoji? _emoji(Object? payload) {
    if (payload is! Map) return null;
    final name = _text(payload['name']);
    if (name == null || name.isEmpty) return null;
    final id = _text(payload['id']);
    final animated = payload['animated'] == true;
    return ActivityEmoji(
      name: name,
      id: id,
      animated: animated,
      imageUrl: id == null
          ? null
          : DiscordCdn.customEmoji(id, animated: animated),
    );
  }

  static ActivityAssets? _assets(Object? payload, String? applicationId) {
    if (payload is! Map) return null;
    final largeImage = _text(payload['large_image']);
    final smallImage = _text(payload['small_image']);
    final assets = ActivityAssets(
      largeImage: largeImage,
      largeText: _text(payload['large_text']),
      largeUrl: _text(payload['large_url']),
      smallImage: smallImage,
      smallText: _text(payload['small_text']),
      smallUrl: _text(payload['small_url']),
      largeImageUrl: DiscordCdn.activityAsset(
        largeImage,
        applicationId: applicationId,
      ),
      smallImageUrl: DiscordCdn.activityAsset(
        smallImage,
        applicationId: applicationId,
      ),
    );
    return assets.isEmpty ? null : assets;
  }

  /// R07's `eP`: `isCountDown` is invented client-side from the end stamp and
  /// `created_at`, and a track being listened to always counts up.
  static ActivityTimestamps? _timestamps(
    Object? payload, {
    required ActivityType type,
    required int? createdAtMs,
  }) {
    if (payload is! Map) return null;
    final start = _int(payload['start']);
    final end = _int(payload['end']);
    if (start == null && end == null) return null;
    return ActivityTimestamps(
      startMs: start,
      endMs: end,
      isCountDown:
          end != null &&
          createdAtMs != null &&
          end > createdAtMs &&
          type != ActivityType.listening,
    );
  }

  static ActivityParty? _party(Object? payload) {
    if (payload is! Map) return null;
    final size = payload['size'];
    final sizes = size is List && size.length == 2
        ? [_int(size[0]), _int(size[1])]
        : const <int?>[null, null];
    final party = ActivityParty(
      id: _text(payload['id']),
      currentSize: sizes[0],
      maxSize: sizes[1],
      privacy: ActivityPartyPrivacy.fromWire(payload['privacy']),
    );
    return party.id == null && !party.hasSize && party.privacy == null
        ? null
        : party;
  }

  static ActivitySecrets? _secrets(Object? payload) {
    if (payload is! Map) return null;
    final match = _text(payload['match']);
    final join = _text(payload['join']);
    if (match == null && join == null) return null;
    return ActivitySecrets(match: match, join: join);
  }

  /// Reads a bitfield without letting a negative number mean "every bit set".
  ///
  /// Activity flags are unsigned on the wire; a `-1` parsed as a signed int
  /// would answer true to every [ActivityFlag] test, including the ones that
  /// unlock join and party-privacy behaviour.
  static int _flags(Object? value) {
    final parsed = _int(value);
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  static List<String> _strings(Object? payload, int limit) {
    if (payload is! List) return const [];
    final mapped = <String>[];
    for (final entry in payload) {
      if (mapped.length == limit) break;
      final text = _text(entry);
      if (text != null && text.isNotEmpty) mapped.add(text);
    }
    return mapped;
  }

  /// Reads a wire string, truncated to [maxTextLength].
  static String? _text(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return value.length <= maxTextLength
        ? value
        : value.substring(0, maxTextLength);
  }

  /// Reads a wire number. Discord sends timestamps as numbers, but a snowflake
  /// -adjacent field occasionally arrives as a decimal string, and a
  /// non-finite double would crash `round()`.
  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is double) return value.isFinite ? value.round() : null;
    if (value is String) return int.tryParse(value);
    return null;
  }
}
