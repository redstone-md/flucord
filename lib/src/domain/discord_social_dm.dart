import 'discord_relationship.dart';

final class DiscordSocialDmConversation {
  const DiscordSocialDmConversation({
    required this.user,
    required this.lastMessageId,
  });

  final DiscordRelationshipUser user;
  final String lastMessageId;
}

final class DiscordSocialDmMessage {
  factory DiscordSocialDmMessage({
    required String id,
    required String conversationUserId,
    required String authorId,
    required String recipientId,
    required String authorDisplayName,
    required String content,
    required DateTime sentAt,
    DateTime? editedAt,
    required bool authoredByCurrentUser,
  }) {
    final normalizedId = id.trim();
    final normalizedConversationUserId = conversationUserId.trim();
    if (normalizedId.isEmpty || normalizedConversationUserId.isEmpty) {
      throw ArgumentError('Social DM identifiers must not be empty.');
    }
    return DiscordSocialDmMessage._(
      id: normalizedId,
      conversationUserId: normalizedConversationUserId,
      authorId: authorId.trim(),
      recipientId: recipientId.trim(),
      authorDisplayName: authorDisplayName.trim(),
      content: content,
      sentAt: sentAt.toUtc(),
      editedAt: editedAt?.toUtc(),
      authoredByCurrentUser: authoredByCurrentUser,
    );
  }

  const DiscordSocialDmMessage._({
    required this.id,
    required this.conversationUserId,
    required this.authorId,
    required this.recipientId,
    required this.authorDisplayName,
    required this.content,
    required this.sentAt,
    required this.editedAt,
    required this.authoredByCurrentUser,
  });

  final String id;
  final String conversationUserId;
  final String authorId;
  final String recipientId;
  final String authorDisplayName;
  final String content;
  final DateTime sentAt;
  final DateTime? editedAt;
  final bool authoredByCurrentUser;

  DiscordSocialDmMessage withContent(String nextContent) =>
      DiscordSocialDmMessage(
        id: id,
        conversationUserId: conversationUserId,
        authorId: authorId,
        recipientId: recipientId,
        authorDisplayName: authorDisplayName,
        content: nextContent,
        sentAt: sentAt,
        editedAt: editedAt,
        authoredByCurrentUser: authoredByCurrentUser,
      );
}

enum DiscordSocialDmEventType { created, updated, deleted }

final class DiscordSocialDmEvent {
  DiscordSocialDmEvent.changed(this.type, DiscordSocialDmMessage changedMessage)
    : message = changedMessage,
      messageId = changedMessage.id;

  const DiscordSocialDmEvent.deleted(this.messageId)
    : type = DiscordSocialDmEventType.deleted,
      message = null;

  final DiscordSocialDmEventType type;
  final String messageId;
  final DiscordSocialDmMessage? message;
}

abstract interface class DiscordSocialDmGateway {
  Future<List<DiscordSocialDmConversation>> fetchConversations();

  Future<List<DiscordSocialDmMessage>> fetchMessages({
    required String userId,
    int limit = 100,
  });

  Future<String> sendMessage({required String userId, required String content});

  Future<void> editMessage({
    required String userId,
    required String messageId,
    required String content,
  });

  Future<void> deleteMessage({
    required String userId,
    required String messageId,
  });

  Future<void> setShowingChat(bool showing);
}

abstract interface class DiscordSocialDmEvents {
  Stream<DiscordSocialDmEvent> get socialDmEvents;
}
