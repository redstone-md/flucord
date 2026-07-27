import '../../domain/chat_models.dart';
import '../../domain/user_settings.dart';

/// Builds the `{status, since, activities, afk}` object this client sends.
///
/// R07 proves opcode 3 and `identify.d.presence` carry the identical object,
/// so there is exactly one composer for both. Everything it needs is passed
/// in: the composition is a pure function of the account's stored status, the
/// idle machine and whatever local activities exist, which is what makes the
/// idle promotion and the invisible-clears-activities rule testable without a
/// socket.
abstract final class DiscordSelfPresence {
  /// The literal name R07 records for the custom-status activity.
  static const customStatusName = 'Custom Status';

  static SelfPresence compose({
    required DateTime now,
    StatusPreferences? stored,
    int? idleSince,
    bool afk = false,
    bool forcedInvisible = false,
    List<UserActivity> localActivities = const [],
  }) {
    final since = idleSince ?? 0;
    var status = forcedInvisible
        ? Presence.invisible
        : _storedStatus(stored?.status);
    // R07's only idle promotion, and it lives here rather than in the idle
    // tracker: a user who chose Do Not Disturb keeps it while idle, and one
    // who chose Online is shown as Idle without their setting being rewritten.
    if (status == Presence.online && since > 0) status = Presence.idle;
    final custom = stored == null ? null : customStatus(stored, now: now);
    return SelfPresence(
      status: status,
      since: since,
      afk: afk,
      // R07: an invisible session broadcasts no activities at all. Sending
      // them anyway would tell every mutual guild exactly what an account that
      // asked to appear offline is doing.
      activities: status == Presence.invisible
          ? const []
          : [?custom, ...localActivities.where(isShareable)],
    );
  }

  /// The custom-status activity, or null when there is nothing to show.
  ///
  /// R07 gates it on the expiry: a status whose `expiresAtMs` has passed is
  /// simply not built, which is what makes a timed status disappear without
  /// the account having to be edited.
  static UserActivity? customStatus(
    StatusPreferences stored, {
    required DateTime now,
  }) {
    if (!stored.hasCustomStatus) return null;
    final expiry = stored.customStatusExpiresAtMs;
    if (expiry > 0 && expiry <= now.millisecondsSinceEpoch) return null;
    final emojiName = stored.customStatusEmojiName;
    final text = stored.customStatusText;
    return UserActivity(
      name: customStatusName,
      type: ActivityType.customStatus,
      state: text == null || text.isEmpty ? null : text,
      timestamps: expiry > 0 ? ActivityTimestamps(endMs: expiry) : null,
      emoji: emojiName == null || emojiName.isEmpty
          ? null
          : ActivityEmoji(
              name: emojiName,
              id: stored.customStatusEmojiId,
              animated: false,
            ),
    );
  }

  /// R07's `isShareable`, reduced to the producers this client has.
  ///
  /// The game-detection, Spotify and Go-Live producers are separate concerns
  /// that do not change the wire contract; until one exists, an activity with
  /// no `application_id` behind it is shareable and one that names an
  /// application is only shareable when the account allows game sharing —
  /// which is the same answer R07's per-app gate gives without a library.
  static bool isShareable(UserActivity activity) =>
      activity.hasFlag(ActivityFlag.contextless) ||
      activity.applicationId == null;

  /// R07: `settings.status.status` unless it is unset or `unknown`.
  static Presence _storedStatus(String? stored) {
    if (stored == null || stored.isEmpty) return Presence.online;
    final parsed = Presence.fromWire(stored);
    return parsed == Presence.unknown ? Presence.online : parsed;
  }

  /// The opcode-3 payload. Exactly four keys — R07 found no others adjacent to
  /// the sender, so anything extra would be this client inventing wire format.
  static Map<String, Object?> toWire(SelfPresence presence) => {
    'status': presence.status.wireValue,
    'since': presence.since,
    'activities': [
      for (final activity in presence.activities) activityToWire(activity),
    ],
    'afk': presence.afk,
  };

  /// The wire form of one outbound activity.
  ///
  /// Only the keys this client actually produces are written. An absent key
  /// and a null one are the same to Discord, and emitting nulls for the twenty
  /// fields a custom status does not use would make every frame larger for no
  /// gain.
  static Map<String, Object?> activityToWire(UserActivity activity) => {
    'name': activity.name,
    'type': activity.type.wireValue,
    'state': ?activity.state,
    'details': ?activity.details,
    'url': ?activity.url,
    'application_id': ?activity.applicationId,
    if (activity.emoji case final emoji?)
      'emoji': {
        'name': emoji.name,
        'id': emoji.isCustom ? emoji.id : null,
        'animated': emoji.animated,
      },
    if (activity.timestamps case final stamps?)
      if (!stamps.isEmpty)
        'timestamps': {'start': ?stamps.startMs, 'end': ?stamps.endMs},
  };
}
