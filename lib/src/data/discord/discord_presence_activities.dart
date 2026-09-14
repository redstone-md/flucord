part of 'discord_presence_store.dart';

/// The ordering and de-duplication rules R07 records for an activity list.
///
/// They are kept apart from the store because they are pure list arithmetic
/// that the profile card and the member row both need to agree with, and
/// because getting the duplicate-`PLAYING` rule wrong is invisible until a
/// user runs a game that Discord has both detected locally and registered over
/// RPC — at which point the roster shows the same title twice.
abstract final class DiscordPresenceActivities {
  /// R07's comparator rank: custom status first, then competing, streaming and
  /// playing, then everything else.
  static int rankOf(ActivityType type) => switch (type) {
    ActivityType.customStatus => 4,
    ActivityType.competing => 3,
    ActivityType.streaming => 2,
    ActivityType.playing => 1,
    _ => 0,
  };

  /// Rank descending, then rich presence first, then newest first.
  static int compare(UserActivity left, UserActivity right) {
    final byRank = rankOf(right.type).compareTo(rankOf(left.type));
    if (byRank != 0) return byRank;
    final byRich = _richness(right).compareTo(_richness(left));
    if (byRich != 0) return byRich;
    return (right.createdAtMs ?? 0).compareTo(left.createdAtMs ?? 0);
  }

  /// Sorts a list Discord sent, leaving a single-entry list untouched.
  static List<UserActivity> sorted(List<UserActivity> activities) {
    if (activities.length < 2) return activities;
    return [...activities]..sort(compare);
  }

  /// R07's hidden-activity dedupe: walk the list backwards keying on
  /// `applicationId:partyId`, keeping the last one seen per key.
  ///
  /// Reversing first is what makes the *first* occurrence in the original list
  /// the survivor, and the output keeps that reversed order — both are
  /// observable in the renderer, so both are reproduced rather than tidied.
  static List<UserActivity> dedupeHidden(List<UserActivity> activities) {
    if (activities.length < 2) return activities;
    final unique = <String, UserActivity>{};
    for (final activity in activities.reversed) {
      unique['${activity.applicationId}:${activity.party?.id}'] = activity;
    }
    return unique.values.toList(growable: false);
  }

  /// R07's duplicate-`PLAYING` filter.
  ///
  /// A detected running game and an RPC activity for the same title both
  /// arrive as `PLAYING`; only the best-ranked one is kept, and the list is
  /// re-sorted afterwards because dropping an entry can change what leads.
  static List<UserActivity> filterDuplicatePlaying(
    List<UserActivity> activities,
  ) {
    UserActivity? bestPlaying;
    var playingCount = 0;
    for (final activity in activities) {
      if (activity.type != ActivityType.playing) continue;
      playingCount++;
      if (bestPlaying == null || compare(activity, bestPlaying) < 0) {
        bestPlaying = activity;
      }
    }
    if (playingCount < 2) return activities;
    return [
      for (final activity in activities)
        if (activity.type != ActivityType.playing) activity,
      bestPlaying!,
    ]..sort(compare);
  }

  static int _richness(UserActivity activity) =>
      activity.isRichPresence ? 1 : 0;
}
