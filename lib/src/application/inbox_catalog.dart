import '../domain/chat_models.dart';
import 'quick_switcher_catalog.dart';

final class InboxSummary {
  const InboxSummary({
    required this.unreadChannelCount,
    required this.mentionCount,
  });

  /// Counts the badge on its own, without building the rest of the inbox.
  ///
  /// One pass over the channels answers both numbers. Reading them off a full
  /// [InboxCatalog] instead walks every message and every member, which is far
  /// too much work for a header badge that rebuilds with the shell.
  factory InboxSummary.fromWorkspace(ChatWorkspace workspace) {
    var unreadChannelCount = 0;
    var mentionCount = 0;
    for (final channel in workspace.channels) {
      if (channel.hasMessageTimeline &&
          (channel.unread || channel.mentionCount > 0)) {
        unreadChannelCount++;
      }
      mentionCount += channel.mentionCount;
    }
    return InboxSummary(
      unreadChannelCount: unreadChannelCount,
      mentionCount: mentionCount,
    );
  }

  static const empty = InboxSummary(unreadChannelCount: 0, mentionCount: 0);

  final int unreadChannelCount;
  final int mentionCount;

  bool get hasUnread => unreadChannelCount > 0;
  bool get hasActivity => hasUnread || mentionCount > 0;
}

final class InboxTarget {
  const InboxTarget({
    required this.spaceId,
    required this.channelId,
    this.messageId,
  });

  final String spaceId;
  final String channelId;
  final String? messageId;
}

final class InboxUnreadEntry {
  const InboxUnreadEntry({
    required this.target,
    required this.path,
    required this.mentionCount,
    required this.firstUnreadMessageId,
    required this.latestActivityAt,
  });

  final InboxTarget target;
  final String path;
  final int mentionCount;
  final String? firstUnreadMessageId;
  final DateTime? latestActivityAt;
}

final class InboxMentionEntry {
  const InboxMentionEntry({
    required this.target,
    required this.path,
    required this.message,
    required this.author,
  });

  final InboxTarget target;
  final String path;
  final ChatMessage message;
  final Member author;
}

/// One unanswered message request, as the folder lists it.
final class InboxRequestEntry {
  const InboxRequestEntry({
    required this.target,
    required this.channel,
    required this.path,
    this.recipient,
    this.requestedAt,
  });

  final InboxTarget target;
  final ConversationChannel channel;

  /// The person on the other side, when the workspace knows them.
  final Member? recipient;
  final String path;
  final DateTime? requestedAt;
}

/// A channel's mentions, as the notification centre groups them.
///
/// The centre reads per channel, not per message: one row per conversation,
/// with the messages under it for jumping.
final class InboxMentionGroup {
  const InboxMentionGroup({
    required this.target,
    required this.path,
    required this.entries,
  });

  /// Jumps to the group's newest mention.
  final InboxTarget target;
  final String path;
  final List<InboxMentionEntry> entries;

  int get mentionCount => entries.length;
}

/// The last catalogue built for a workspace, so a rebuilt dialog can reuse it.
final _inboxByWorkspace = Expando<({int mentionLimit, InboxCatalog catalog})>();

final class InboxCatalog {
  InboxCatalog._({
    required this.summary,
    required List<InboxUnreadEntry> unread,
    required List<InboxMentionEntry> mentions,
    required List<InboxMentionGroup> mentionGroups,
    required List<InboxRequestEntry> requests,
  }) : unread = List.unmodifiable(unread),
       mentions = List.unmodifiable(mentions),
       mentionGroups = List.unmodifiable(mentionGroups),
       requests = List.unmodifiable(requests);

  /// Builds the inbox for [workspace], reusing the last catalogue built for it.
  ///
  /// The dialog rebuilds on every chat controller notification, and a workspace
  /// never changes once created, so the previous catalogue stays correct until a
  /// new workspace replaces it.
  factory InboxCatalog.fromWorkspace(
    ChatWorkspace workspace, {
    int maxMentions = 50,
  }) {
    final mentionLimit = maxMentions < 0 ? 0 : maxMentions;
    final cached = _inboxByWorkspace[workspace];
    if (cached != null && cached.mentionLimit == mentionLimit) {
      return cached.catalog;
    }
    final catalog = _build(workspace, mentionLimit);
    _inboxByWorkspace[workspace] = (
      mentionLimit: mentionLimit,
      catalog: catalog,
    );
    return catalog;
  }

  static InboxCatalog _build(ChatWorkspace workspace, int mentionLimit) {
    final paths = <String, String>{
      for (final destination in QuickSwitcherCatalog.fromWorkspace(
        workspace,
      ).destinations.where((destination) => destination.channelId != null))
        destination.channelId!: destination.path,
    };
    final messagesByChannel = <String, List<ChatMessage>>{};
    for (final message in workspace.messages) {
      messagesByChannel.putIfAbsent(message.channelId, () => []).add(message);
    }

    final unread =
        workspace.channels
            .where(
              (channel) =>
                  channel.hasMessageTimeline &&
                  (channel.unread || channel.mentionCount > 0),
            )
            .map((channel) {
              final messages = messagesByChannel[channel.id] ?? const [];
              return InboxUnreadEntry(
                target: InboxTarget(
                  spaceId: channel.spaceId,
                  channelId: channel.id,
                  messageId: channel.firstUnreadMessageId,
                ),
                path: paths[channel.id] ?? channel.name,
                mentionCount: channel.mentionCount,
                firstUnreadMessageId: channel.firstUnreadMessageId,
                latestActivityAt: messages.isEmpty
                    ? null
                    : messages.last.sentAt,
              );
            })
            .toList(growable: false)
          ..sort(_compareUnread);

    final channelById = {
      for (final channel in workspace.channels) channel.id: channel,
    };
    final mentions =
        workspace.messages
            .map(
              (message) => (message, workspace.memberOrNull(message.authorId)),
            )
            .where(
              (entry) =>
                  entry.$1.mentionsCurrentMember &&
                  entry.$1.authorId != workspace.currentMemberId &&
                  channelById.containsKey(entry.$1.channelId) &&
                  entry.$2 != null,
            )
            .map((entry) {
              final message = entry.$1;
              final channel = channelById[message.channelId]!;
              return InboxMentionEntry(
                target: InboxTarget(
                  spaceId: channel.spaceId,
                  channelId: channel.id,
                  messageId: message.id,
                ),
                path: paths[channel.id] ?? channel.name,
                message: message,
                author: entry.$2!,
              );
            })
            .toList(growable: false)
          ..sort(
            (left, right) =>
                right.message.sentAt.compareTo(left.message.sentAt),
          );
    final limitedMentions = mentions.length > mentionLimit
        ? mentions.sublist(0, mentionLimit)
        : mentions;
    // The flat list stays capped; the groups fold whatever survived it, so a
    // cap smaller than the mention count still reads per channel.
    final mentionGroups = _groupMentions(limitedMentions);
    final requests =
        workspace.channels
            .where((channel) => channel.isMessageRequest)
            .map((channel) {
              final recipientId = channel.recipientId;
              final recipient = recipientId == null
                  ? null
                  : workspace.memberOrNull(recipientId);
              return InboxRequestEntry(
                target: InboxTarget(
                  spaceId: channel.spaceId,
                  channelId: channel.id,
                ),
                channel: channel,
                recipient: recipient,
                path: recipient?.displayName ?? channel.name,
                requestedAt: channel.messageRequestedAt,
              );
            })
            .toList(growable: false)
          ..sort(_compareRequests);
    return InboxCatalog._(
      summary: InboxSummary.fromWorkspace(workspace),
      unread: unread,
      mentions: limitedMentions,
      mentionGroups: mentionGroups,
      requests: requests,
    );
  }

  /// Folds a newest-first mention list into per-channel groups, keeping the
  /// list's order: the group of the newest mention leads, and so on.
  static List<InboxMentionGroup> _groupMentions(
    List<InboxMentionEntry> mentions,
  ) {
    final groups = <String, InboxMentionGroup>{};
    for (final entry in mentions) {
      final channelId = entry.target.channelId;
      final group = groups[channelId];
      groups[channelId] = group == null
          ? InboxMentionGroup(
              target: entry.target,
              path: entry.path,
              entries: [entry],
            )
          : InboxMentionGroup(
              target: group.target,
              path: group.path,
              entries: [...group.entries, entry],
            );
    }
    return groups.values.toList(growable: false);
  }

  /// Newest request first. A request that arrived without a timestamp keeps a
  /// stable place behind the dated ones, ordered by channel id.
  static int _compareRequests(InboxRequestEntry left, InboxRequestEntry right) {
    final leftAt = left.requestedAt;
    final rightAt = right.requestedAt;
    if (leftAt == null || rightAt == null) {
      if (leftAt != rightAt) return leftAt == null ? 1 : -1;
      return right.target.channelId.compareTo(left.target.channelId);
    }
    final byTime = rightAt.compareTo(leftAt);
    return byTime != 0
        ? byTime
        : right.target.channelId.compareTo(left.target.channelId);
  }

  final InboxSummary summary;
  final List<InboxUnreadEntry> unread;
  final List<InboxMentionEntry> mentions;

  /// The same mentions folded per channel, as the notification centre reads.
  final List<InboxMentionGroup> mentionGroups;

  /// The conversations waiting in the message-request folder.
  final List<InboxRequestEntry> requests;

  /// Whether the account has anything waiting in the request folder.
  bool get hasRequests => requests.isNotEmpty;

  static int _compareUnread(InboxUnreadEntry left, InboxUnreadEntry right) {
    final mentions = right.mentionCount.compareTo(left.mentionCount);
    if (mentions != 0) return mentions;
    final leftTime = left.latestActivityAt;
    final rightTime = right.latestActivityAt;
    if (leftTime == null) return rightTime == null ? 0 : 1;
    if (rightTime == null) return -1;
    return rightTime.compareTo(leftTime);
  }
}
