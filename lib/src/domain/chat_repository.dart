import 'chat_models.dart';

enum RepositoryConnectionStatus { offline, connecting, connected, reconnecting }

sealed class ChatRepositoryEvent {
  const ChatRepositoryEvent();
}

final class MessageUpsertedEvent extends ChatRepositoryEvent {
  const MessageUpsertedEvent({required this.message, this.member});

  final ChatMessage message;
  final Member? member;
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

  Future<ChannelHistory> loadChannelHistory(String channelId);

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

  Future<void> close();
}
