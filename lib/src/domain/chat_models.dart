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
    this.unread = false,
    this.mentionCount = 0,
  });

  final String id;
  final String spaceId;
  final String name;
  final String topic;
  final ChannelKind kind;
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

final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.body,
    required this.sentAt,
    this.isEdited = false,
  });

  final String id;
  final String channelId;
  final String authorId;
  final String body;
  final DateTime sentAt;
  final bool isEdited;
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
