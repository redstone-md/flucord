part of 'chat_models.dart';

const _keepUnreadBoundary = Object();
const _keepLastMessageId = Object();

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
    this.isStage = false,
    this.isArchived = false,
    this.isLocked = false,
    this.archiveTimestamp,
    this.autoArchiveDurationMinutes,
    this.availableTags = const [],
    this.appliedTagIds = const [],
    this.defaultAutoArchiveDurationMinutes,
    this.defaultSortOrder,
    this.defaultForumLayout,
    this.recipientId,
    this.unread = false,
    this.mentionCount = 0,
    this.firstUnreadMessageId,
    this.lastMessageId,
    this.permissionOverwrites = const {},
  });

  final String id;
  final String spaceId;
  final String name;
  final String topic;
  final ChannelKind kind;
  final int position;
  final String? parentId;
  final bool isThread;

  /// A stage channel: a voice channel where only speakers may talk and
  /// everyone else has to ask. Discord types it separately (13), and the
  /// distinction changes what the room offers, so it is carried rather than
  /// flattened into [ChannelKind.voice].
  final bool isStage;
  final bool isArchived;
  final bool isLocked;
  final DateTime? archiveTimestamp;
  final int? autoArchiveDurationMinutes;
  final List<ForumTag> availableTags;
  final List<String> appliedTagIds;
  final int? defaultAutoArchiveDurationMinutes;
  final ForumSortOrder? defaultSortOrder;
  final ForumLayout? defaultForumLayout;
  final String? recipientId;
  final bool unread;
  final int mentionCount;
  final String? firstUnreadMessageId;

  /// The newest message Discord says this channel holds.
  ///
  /// Unread is a comparison, not a flag: a channel is unread when this id is
  /// newer than the read state's ack cursor. Keeping the pointer on the channel
  /// is what lets that comparison survive a restart, because the client can
  /// answer it without having loaded a single message.
  final String? lastMessageId;

  /// The channel's permission overwrites, keyed by role or member id.
  ///
  /// A thread carries none that matter: Discord resolves a thread's
  /// permissions from its parent and never reads the thread's own map.
  final Map<String, DiscordPermissionOverwrite> permissionOverwrites;

  bool get isDirectMessage => recipientId != null;

  /// A voice channel carries an ordinary message timeline on the same channel
  /// id as the room, so every message-shaped feature has to treat it like a
  /// text channel. Forum and media channels look similar but are threads-only
  /// containers: their messages live in posts, never on the parent id, so they
  /// deliberately stay out.
  bool get hasMessageTimeline =>
      kind == ChannelKind.text || kind == ChannelKind.voice;

  bool get canAcceptMessageForward =>
      hasMessageTimeline && !(isThread && isArchived && isLocked);

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
    // A `CHANNEL_UPDATE` carries the whole channel but not always its
    // `last_message_id`; dropping the remembered one would make every unread
    // channel look read until the next message arrived.
    lastMessageId: lastMessageId ?? previous.lastMessageId,
  );

  /// Records that [messageId] is the newest message here, never rewinding.
  ConversationChannel withLatestMessage(String messageId) =>
      lastMessageId != null &&
          DiscordSnowflake.compare(messageId, lastMessageId!) <= 0
      ? this
      : copyWith(lastMessageId: messageId);

  ConversationChannel copyWith({
    bool? unread,
    int? mentionCount,
    bool? isArchived,
    bool? isLocked,
    DateTime? archiveTimestamp,
    int? autoArchiveDurationMinutes,
    List<ForumTag>? availableTags,
    List<String>? appliedTagIds,
    int? defaultAutoArchiveDurationMinutes,
    ForumSortOrder? defaultSortOrder,
    ForumLayout? defaultForumLayout,
    Object? firstUnreadMessageId = _keepUnreadBoundary,
    Object? lastMessageId = _keepLastMessageId,
  }) => ConversationChannel(
    id: id,
    spaceId: spaceId,
    name: name,
    topic: topic,
    kind: kind,
    position: position,
    parentId: parentId,
    isThread: isThread,
    isStage: isStage,
    isArchived: isArchived ?? this.isArchived,
    isLocked: isLocked ?? this.isLocked,
    archiveTimestamp: archiveTimestamp ?? this.archiveTimestamp,
    autoArchiveDurationMinutes:
        autoArchiveDurationMinutes ?? this.autoArchiveDurationMinutes,
    availableTags: availableTags ?? this.availableTags,
    appliedTagIds: appliedTagIds ?? this.appliedTagIds,
    defaultAutoArchiveDurationMinutes:
        defaultAutoArchiveDurationMinutes ??
        this.defaultAutoArchiveDurationMinutes,
    defaultSortOrder: defaultSortOrder ?? this.defaultSortOrder,
    defaultForumLayout: defaultForumLayout ?? this.defaultForumLayout,
    recipientId: recipientId,
    permissionOverwrites: permissionOverwrites,
    unread: unread ?? this.unread,
    mentionCount: mentionCount ?? this.mentionCount,
    firstUnreadMessageId: identical(firstUnreadMessageId, _keepUnreadBoundary)
        ? this.firstUnreadMessageId
        : firstUnreadMessageId as String?,
    lastMessageId: identical(lastMessageId, _keepLastMessageId)
        ? this.lastMessageId
        : lastMessageId as String?,
  );
}
