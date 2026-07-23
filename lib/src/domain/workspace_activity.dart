import 'chat_models.dart';

final class SpaceActivity {
  const SpaceActivity({required this.unread, required this.mentionCount});

  static const none = SpaceActivity(unread: false, mentionCount: 0);

  final bool unread;
  final int mentionCount;

  bool get hasUnread => unread || mentionCount > 0;
}

extension WorkspaceActivity on ChatWorkspace {
  Map<String, SpaceActivity> activityBySpace() {
    final unreadSpaceIds = <String>{};
    final mentionsBySpaceId = <String, int>{};
    for (final channel in channels) {
      if (channel.unread) unreadSpaceIds.add(channel.spaceId);
      if (channel.mentionCount > 0) {
        mentionsBySpaceId.update(
          channel.spaceId,
          (count) => count + channel.mentionCount,
          ifAbsent: () => channel.mentionCount,
        );
      }
    }
    final activeSpaceIds = {...unreadSpaceIds, ...mentionsBySpaceId.keys};
    return Map.unmodifiable({
      for (final spaceId in activeSpaceIds)
        spaceId: SpaceActivity(
          unread: unreadSpaceIds.contains(spaceId),
          mentionCount: mentionsBySpaceId[spaceId] ?? 0,
        ),
    });
  }
}
