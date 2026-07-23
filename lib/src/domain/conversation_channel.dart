part of 'chat_models.dart';

const _keepUnreadBoundary = Object();

final class ConversationChannel {
  const ConversationChannel({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.topic,
    required this.kind,
    this.position = 0,
    this.parentId,
    this.isThread = false,
    this.recipientId,
    this.unread = false,
    this.mentionCount = 0,
    this.firstUnreadMessageId,
  });

  final String id;
  final String spaceId;
  final String name;
  final String topic;
  final ChannelKind kind;
  final int position;
  final String? parentId;
  final bool isThread;
  final String? recipientId;
  final bool unread;
  final int mentionCount;
  final String? firstUnreadMessageId;

  bool get isDirectMessage => recipientId != null;

  ConversationChannel markUnread({
    required String messageId,
    required bool mention,
  }) => copyWith(
    unread: true,
    mentionCount: mention ? mentionCount + 1 : mentionCount,
    firstUnreadMessageId: firstUnreadMessageId ?? messageId,
  );

  ConversationChannel markRead() => copyWith(unread: false, mentionCount: 0);

  ConversationChannel clearUnreadBoundary() =>
      copyWith(firstUnreadMessageId: null);

  ConversationChannel withActivityOf(ConversationChannel previous) => copyWith(
    unread: previous.unread,
    mentionCount: previous.mentionCount,
    firstUnreadMessageId: previous.firstUnreadMessageId,
  );

  ConversationChannel copyWith({
    bool? unread,
    int? mentionCount,
    Object? firstUnreadMessageId = _keepUnreadBoundary,
  }) => ConversationChannel(
    id: id,
    spaceId: spaceId,
    name: name,
    topic: topic,
    kind: kind,
    position: position,
    parentId: parentId,
    isThread: isThread,
    recipientId: recipientId,
    unread: unread ?? this.unread,
    mentionCount: mentionCount ?? this.mentionCount,
    firstUnreadMessageId: identical(firstUnreadMessageId, _keepUnreadBoundary)
        ? this.firstUnreadMessageId
        : firstUnreadMessageId as String?,
  );
}
