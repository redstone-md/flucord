part of 'chat_controller.dart';

extension ChatControllerReactions on ChatController {
  /// Whether this session's transport can list who reacted.
  bool get canListReactionUsers => _repository is ReactionRepository;

  /// Whether this session's transport can send super reactions at all. The
  /// account also needs Nitro, which the caller checks.
  bool get canSendSuperReactions => _repository is SuperReactionRepository;

  /// Adds the account's super reaction to [reaction], or takes it back.
  Future<void> toggleSuperReaction(
    ChatMessage message,
    MessageReaction reaction,
  ) async {
    if (_repository case final SuperReactionRepository repository) {
      await (reaction.burstByCurrentUser
          ? repository.removeSuperReaction(
              channelId: message.channelId,
              messageId: message.id,
              emoji: reaction.key,
            )
          : repository.addSuperReaction(
              channelId: message.channelId,
              messageId: message.id,
              emoji: reaction.key,
            ));
    }
  }

  Future<void> addSuperReaction(ChatMessage message, String emoji) async {
    if (_repository case final SuperReactionRepository repository) {
      await repository.addSuperReaction(
        channelId: message.channelId,
        messageId: message.id,
        emoji: emoji,
      );
    }
  }

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
