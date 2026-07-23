enum ChannelKind { text, voice }

enum Presence { online, idle, offline }

final class CommunitySpace {
  const CommunitySpace({
    required this.id,
    required this.name,
    required this.monogram,
    required this.colorValue,
  });

  final String id;
  final String name;
  final String monogram;
  final int colorValue;
}

final class ConversationChannel {
  const ConversationChannel({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.topic,
    required this.kind,
    this.parentId,
    this.isThread = false,
    this.unread = false,
    this.mentionCount = 0,
  });

  final String id;
  final String spaceId;
  final String name;
  final String topic;
  final ChannelKind kind;
  final String? parentId;
  final bool isThread;
  final bool unread;
  final int mentionCount;
}

final class Member {
  const Member({
    required this.id,
    required this.displayName,
    required this.initials,
    required this.role,
    required this.presence,
    required this.colorValue,
  });

  final String id;
  final String displayName;
  final String initials;
  final String role;
  final Presence presence;
  final int colorValue;
}

final class PendingAttachment {
  const PendingAttachment({
    required this.name,
    required this.path,
    required this.size,
  });

  final String name;
  final String path;
  final int size;
}

final class MessageAttachment {
  const MessageAttachment({
    required this.id,
    required this.fileName,
    required this.url,
    required this.size,
    this.contentType,
    this.width,
    this.height,
  });

  final String id;
  final String fileName;
  final String url;
  final int size;
  final String? contentType;
  final int? width;
  final int? height;

  bool get isImage => contentType?.startsWith('image/') ?? false;
}

final class MessageReply {
  const MessageReply({
    required this.messageId,
    required this.authorId,
    required this.body,
  });

  final String messageId;
  final String authorId;
  final String body;
}

final class MessageReaction {
  const MessageReaction({
    required this.emojiName,
    required this.count,
    this.emojiId,
    this.animated = false,
    this.reactedByCurrentUser = false,
  });

  final String emojiName;
  final String? emojiId;
  final int count;
  final bool animated;
  final bool reactedByCurrentUser;

  String get key => emojiId == null ? emojiName : '$emojiName:$emojiId';

  MessageReaction copyWith({int? count, bool? reactedByCurrentUser}) =>
      MessageReaction(
        emojiName: emojiName,
        emojiId: emojiId,
        count: count ?? this.count,
        animated: animated,
        reactedByCurrentUser: reactedByCurrentUser ?? this.reactedByCurrentUser,
      );
}

final class ChatMessage {
  ChatMessage({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.body,
    required this.sentAt,
    List<MessageAttachment> attachments = const [],
    List<MessageReaction> reactions = const [],
    this.reply,
    this.isEdited = false,
  }) : attachments = List.unmodifiable(attachments),
       reactions = List.unmodifiable(reactions);

  final String id;
  final String channelId;
  final String authorId;
  final String body;
  final DateTime sentAt;
  final List<MessageAttachment> attachments;
  final MessageReply? reply;
  final List<MessageReaction> reactions;
  final bool isEdited;

  ChatMessage copyWith({
    String? body,
    List<MessageAttachment>? attachments,
    List<MessageReaction>? reactions,
    bool? isEdited,
  }) => ChatMessage(
    id: id,
    channelId: channelId,
    authorId: authorId,
    body: body ?? this.body,
    sentAt: sentAt,
    attachments: attachments ?? this.attachments,
    reply: reply,
    reactions: reactions ?? this.reactions,
    isEdited: isEdited ?? this.isEdited,
  );
}

final class ChatWorkspace {
  ChatWorkspace({
    required List<CommunitySpace> spaces,
    required List<ConversationChannel> channels,
    required List<Member> members,
    required List<ChatMessage> messages,
    required this.currentMemberId,
  }) : spaces = List.unmodifiable(spaces),
       channels = List.unmodifiable(channels),
       members = List.unmodifiable(members),
       messages = List.unmodifiable(messages);

  final List<CommunitySpace> spaces;
  final List<ConversationChannel> channels;
  final List<Member> members;
  final List<ChatMessage> messages;
  final String currentMemberId;

  List<ConversationChannel> channelsFor(String spaceId) => channels
      .where((channel) => channel.spaceId == spaceId)
      .toList(growable: false);

  List<ChatMessage> messagesFor(String channelId) => messages
      .where((message) => message.channelId == channelId)
      .toList(growable: false);

  CommunitySpace spaceById(String id) =>
      spaces.firstWhere((space) => space.id == id);

  ConversationChannel channelById(String id) =>
      channels.firstWhere((channel) => channel.id == id);

  Member memberById(String id) =>
      members.firstWhere((member) => member.id == id);

  Member? memberOrNull(String id) {
    for (final member in members) {
      if (member.id == id) return member;
    }
    return null;
  }

  ChatWorkspace copyWith({
    List<CommunitySpace>? spaces,
    List<ConversationChannel>? channels,
    List<Member>? members,
    List<ChatMessage>? messages,
    String? currentMemberId,
  }) => ChatWorkspace(
    spaces: spaces ?? this.spaces,
    channels: channels ?? this.channels,
    members: members ?? this.members,
    messages: messages ?? this.messages,
    currentMemberId: currentMemberId ?? this.currentMemberId,
  );

  ChatWorkspace mergeHistory(ChannelHistory history) {
    final memberMap = {for (final member in members) member.id: member};
    for (final member in history.members) {
      memberMap[member.id] = member;
    }
    final nextMessages = messages
        .where((message) => message.channelId != history.channelId)
        .toList();
    nextMessages.addAll(history.messages);
    nextMessages.sort((left, right) => left.sentAt.compareTo(right.sentAt));
    return copyWith(members: memberMap.values.toList(), messages: nextMessages);
  }

  ChatWorkspace upsertMessage(ChatMessage message, {Member? member}) {
    final nextMessages = [
      ...messages.where((existing) => existing.id != message.id),
      message,
    ]..sort((left, right) => left.sentAt.compareTo(right.sentAt));
    final nextMembers = member == null
        ? members
        : [...members.where((existing) => existing.id != member.id), member];
    return copyWith(messages: nextMessages, members: nextMembers);
  }

  ChatWorkspace removeMessage(String messageId) => copyWith(
    messages: messages.where((message) => message.id != messageId).toList(),
  );

  ChatWorkspace upsertChannel(ConversationChannel channel) => copyWith(
    channels: [
      ...channels.where((existing) => existing.id != channel.id),
      channel,
    ],
  );

  ChatWorkspace removeChannel(String channelId) => copyWith(
    channels: channels.where((channel) => channel.id != channelId).toList(),
    messages: messages
        .where((message) => message.channelId != channelId)
        .toList(),
  );
}

final class ChannelHistory {
  ChannelHistory({
    required this.channelId,
    required List<ChatMessage> messages,
    required List<Member> members,
  }) : messages = List.unmodifiable(messages),
       members = List.unmodifiable(members);

  final String channelId;
  final List<ChatMessage> messages;
  final List<Member> members;
}
