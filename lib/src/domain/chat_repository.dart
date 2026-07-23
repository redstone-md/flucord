import 'chat_models.dart';

enum RepositoryConnectionStatus { offline, connecting, connected, reconnecting }

sealed class ChatRepositoryEvent {
  const ChatRepositoryEvent();
}

final class MessageUpsertedEvent extends ChatRepositoryEvent {
  const MessageUpsertedEvent({
    required this.message,
    this.member,
    this.isNew = false,
    this.mentionsCurrentMember = false,
  });

  final ChatMessage message;
  final Member? member;
  final bool isNew;
  final bool mentionsCurrentMember;
}

final class MemberUpsertedEvent extends ChatRepositoryEvent {
  const MemberUpsertedEvent(this.member);

  final Member member;
}

final class MemberRemovedEvent extends ChatRepositoryEvent {
  const MemberRemovedEvent({required this.memberId, required this.spaceId});

  final String memberId;
  final String spaceId;
}

final class PresenceChangedEvent extends ChatRepositoryEvent {
  const PresenceChangedEvent({required this.memberId, required this.presence});

  final String memberId;
  final Presence presence;
}

final class TypingStartedEvent extends ChatRepositoryEvent {
  const TypingStartedEvent({required this.channelId, required this.memberId});

  final String channelId;
  final String memberId;
}

final class PinsChangedEvent extends ChatRepositoryEvent {
  const PinsChangedEvent(this.channelId);

  final String channelId;
}

final class MessageDeletedEvent extends ChatRepositoryEvent {
  const MessageDeletedEvent({required this.messageId, required this.channelId});

  final String messageId;
  final String channelId;
}

final class ChannelUpsertedEvent extends ChatRepositoryEvent {
  const ChannelUpsertedEvent(this.channel);

  final ConversationChannel channel;
}

final class SpaceUpsertedEvent extends ChatRepositoryEvent {
  const SpaceUpsertedEvent(this.space);

  final CommunitySpace space;
}

final class ChannelDeletedEvent extends ChatRepositoryEvent {
  const ChannelDeletedEvent(this.channelId);

  final String channelId;
}

final class RepositoryStatusChangedEvent extends ChatRepositoryEvent {
  const RepositoryStatusChangedEvent(this.status);

  final RepositoryConnectionStatus status;
}

abstract interface class ChatRepository {
  Stream<ChatRepositoryEvent> get events;

  Future<ChatWorkspace> loadWorkspace();

  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  });

  Future<ChannelHistory> loadPinnedMessages(String channelId);

  Future<DirectConversation> openDirectConversation(String recipientId);

  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
  });

  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  });

  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  });

  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  });

  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  });

  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  });

  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  });

  Future<void> startTyping(String channelId);

  Future<void> close();
}
