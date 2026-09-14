part of 'chat_controller.dart';

extension ChatControllerReactions on ChatController {
  Future<ReactionUsersPage> loadReactionUsers(
    ChatMessage message,
    MessageReaction reaction,
    DiscordReactionType type,
    String? afterUserId,
  ) {
    final repository = _repository;
    if (repository is! ReactionRepository) {
      return Future.value(const ReactionUsersPage(users: [], hasMore: false));
    }
    return (repository as ReactionRepository).loadReactionUsers(
      channelId: message.channelId,
      messageId: message.id,
      emoji: reaction.key,
      type: type,
      afterUserId: afterUserId,
    );
  }
}
