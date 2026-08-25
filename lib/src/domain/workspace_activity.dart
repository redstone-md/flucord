import 'chat_models.dart';
import 'read_state.dart';

final class SpaceActivity {
  const SpaceActivity({
    required this.unread,
    required this.mentionCount,
    this.muted = false,
  });

  static const none = SpaceActivity(unread: false, mentionCount: 0);

  final bool unread;
  final int mentionCount;

  /// The space is muted, which is why the rail dims it rather than pipping it.
  final bool muted;

  bool get hasUnread => unread || mentionCount > 0;

  /// Compared by value so a rolled-up map can be checked against the last one,
  /// which is how the rail decides it has nothing to redraw.
  @override
  bool operator ==(Object other) =>
      other is SpaceActivity &&
      other.unread == unread &&
      other.mentionCount == mentionCount &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(unread, mentionCount, muted);
}

/// The last roll-up built for a workspace, so a rebuilt rail can reuse it.
final _activityByWorkspace =
    Expando<
      ({ReadStateSnapshot? readState, Map<String, SpaceActivity> activity})
    >();

extension WorkspaceActivity on ChatWorkspace {
  /// Rolls each space's channels up into one pip.
  ///
  /// [readState] decides which channels count. R04 resolves an unread badge
  /// per channel — a channel set to "only mentions" is unread on the server and
  /// silent in the rail — and a muted space keeps its mention badge while
  /// losing its pip, which is the distinction the official client draws.
  ///
  /// The rail rebuilds far more often than either input changes, so the last
  /// roll-up is kept and handed back until a new workspace or read state
  /// arrives.
  Map<String, SpaceActivity> activityBySpace({ReadStateSnapshot? readState}) {
    final cached = _activityByWorkspace[this];
    if (cached != null && identical(cached.readState, readState)) {
      return cached.activity;
    }
    final activity = _rollUp(readState);
    _activityByWorkspace[this] = (readState: readState, activity: activity);
    return activity;
  }

  Map<String, SpaceActivity> _rollUp(ReadStateSnapshot? readState) {
    final snapshot = readState;
    final unreadSpaceIds = <String>{};
    final mentionsBySpaceId = <String, int>{};
    final mutedSpaceIds = <String>{
      if (snapshot != null)
        for (final space in spaces)
          if (snapshot.isSpaceMuted(space.id)) space.id,
    };
    for (final channel in channels) {
      final counts =
          channel.unread &&
          (snapshot == null ||
              (snapshot.unreadBadgeFor(channel) == UnreadBadge.allMessages &&
                  !snapshot.isChannelMuted(channel)));
      if (counts) unreadSpaceIds.add(channel.spaceId);
      if (channel.mentionCount > 0) {
        mentionsBySpaceId.update(
          channel.spaceId,
          (count) => count + channel.mentionCount,
          ifAbsent: () => channel.mentionCount,
        );
      }
    }
    final activeSpaceIds = {
      ...unreadSpaceIds,
      ...mentionsBySpaceId.keys,
      ...mutedSpaceIds,
    };
    return Map.unmodifiable({
      for (final spaceId in activeSpaceIds)
        spaceId: SpaceActivity(
          unread:
              unreadSpaceIds.contains(spaceId) &&
              !mutedSpaceIds.contains(spaceId),
          mentionCount: mentionsBySpaceId[spaceId] ?? 0,
          muted: mutedSpaceIds.contains(spaceId),
        ),
    });
  }
}
