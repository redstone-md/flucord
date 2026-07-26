import 'discord_snowflake.dart';

/// Orders private channels the way Discord's own DM sort store does.
///
/// The DM list is never ordered by its recipients: each channel is keyed on an
/// effective last-message snowflake and the list runs descending by that
/// snowflake's timestamp. The fallback chain behind the key is the part worth
/// reproducing — a conversation nobody has written in still needs a stable
/// place, so the channel id stands in for the message that never existed.
abstract final class DiscordPrivateChannelOrder {
  /// The snowflake a channel's position in the DM list is computed from.
  ///
  /// [readStateLastMessageIds] is the per-channel read-state cursor and wins
  /// over the channel record, matching Discord's priority. Flucord has no
  /// read-state store yet, so the map is normally empty; it is the seam that
  /// phase plugs into.
  static String effectiveLastMessageId(
    Map<String, Object?> channel, {
    Map<String, String> readStateLastMessageIds = const {},
  }) {
    final id = _id(channel);
    var lastMessageId =
        readStateLastMessageIds[id] ?? _lastMessageId(channel) ?? id;
    // An unanswered message request has no message to sort by, so Discord
    // promotes the request's own timestamp into snowflake space and keeps
    // whichever of the two is newer.
    if (channel['is_message_request_timestamp'] case final String requestedAt) {
      final requested = DateTime.tryParse(requestedAt);
      if (requested != null) {
        final candidate = DiscordSnowflake.fromTimestampMillis(
          requested.millisecondsSinceEpoch,
        );
        if (DiscordSnowflake.compare(candidate, lastMessageId) > 0) {
          lastMessageId = candidate;
        }
      }
    }
    return lastMessageId;
  }

  /// Sorts [channels] by descending activity, newest conversation first.
  static List<Map<String, Object?>> sorted(
    Iterable<Map<String, Object?>> channels, {
    Map<String, String> readStateLastMessageIds = const {},
  }) {
    final ranked = [
      for (final channel in channels)
        (
          channel: channel,
          id: _id(channel),
          activity: DiscordSnowflake.timestampMillis(
            effectiveLastMessageId(
              channel,
              readStateLastMessageIds: readStateLastMessageIds,
            ),
          ),
        ),
    ];
    // Discord keys the sort on the timestamp alone, which leaves channels that
    // were last active in the same millisecond tied. Breaking that tie on the
    // channel id keeps the rendered list from reshuffling between rebuilds.
    ranked.sort((left, right) {
      final byActivity = right.activity.compareTo(left.activity);
      if (byActivity != 0) return byActivity;
      final bySnowflake = DiscordSnowflake.compare(right.id, left.id);
      return bySnowflake != 0 ? bySnowflake : right.id.compareTo(left.id);
    });
    return [for (final entry in ranked) entry.channel];
  }

  static String _id(Map<String, Object?> channel) {
    final id = channel['id'];
    return id is String ? id : '';
  }

  static String? _lastMessageId(Map<String, Object?> channel) {
    final id = channel['last_message_id'];
    return id is String && id.isNotEmpty ? id : null;
  }
}
