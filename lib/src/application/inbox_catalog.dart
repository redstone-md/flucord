import '../domain/chat_models.dart';
import 'quick_switcher_catalog.dart';

final class InboxSummary {
  const InboxSummary({
    required this.unreadChannelCount,
    required this.mentionCount,
  });

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

final class InboxCatalog {
  InboxCatalog._({
    required this.summary,
    required List<InboxUnreadEntry> unread,
    required List<InboxMentionEntry> mentions,
  }) : unread = List.unmodifiable(unread),
       mentions = List.unmodifiable(mentions);

  factory InboxCatalog.fromWorkspace(
    ChatWorkspace workspace, {
    int maxMentions = 50,
  }) {
    final mentionLimit = maxMentions < 0 ? 0 : maxMentions;
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
                  channel.kind == ChannelKind.text &&
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
    return InboxCatalog._(
      summary: InboxSummary(
        unreadChannelCount: unread.length,
        mentionCount: workspace.channels.fold(
          0,
          (total, channel) => total + channel.mentionCount,
        ),
      ),
      unread: unread,
      mentions: limitedMentions,
    );
  }

  final InboxSummary summary;
  final List<InboxUnreadEntry> unread;
  final List<InboxMentionEntry> mentions;

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
