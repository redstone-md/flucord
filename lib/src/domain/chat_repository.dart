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
  });

  Future<void> close();
}
