part of 'read_state.dart';

/// The 30-day cleanup that keeps a long-lived account's read state flat.
///
/// A read state whose newest acknowledged message is older than 30 days says
/// nothing the account can still act on: everything it remembers was read at
/// least a month ago. Discord's own client deletes those entries and does so
/// once per application start, which is the schedule this collector keeps.
///
/// An entry still carrying mention badges survives: its badge is live state,
/// and the collector runs before the client knows any channel's newest
/// message, so an unread question it cannot answer is one it declines to
/// guess at.
abstract final class ReadStateCollector {
  /// How old an acknowledged message must be before its read state goes.
  static const maxAge = Duration(days: 30);

  /// The channel ids whose read states [now] makes collectable, oldest first.
  static List<String> collectableChannelIds(
    ReadStateSnapshot snapshot,
    DateTime now,
  ) {
    final cutoff = now.subtract(maxAge).millisecondsSinceEpoch;
    final collectable = [
      for (final state in snapshot.readStates.values)
        if (_isCollectable(state, cutoff)) state.entityId,
    ]..sort(DiscordSnowflake.compare);
    return collectable;
  }

  static bool _isCollectable(ReadState state, int cutoffMillis) {
    if (state.type != ReadStateType.channel) return false;
    if (state.hasMentions) return false;
    final acked = state.lastAckedId;
    if (acked == null) return false;
    return DiscordSnowflake.timestampMillis(acked) < cutoffMillis;
  }
}
