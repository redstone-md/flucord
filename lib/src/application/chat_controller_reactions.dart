part of 'chat_controller.dart';

extension ChatControllerReactions on ChatController {
  /// Whether this session's transport can list who reacted.
  bool get canListReactionUsers => _repository is ReactionRepository;

  /// Whether this session's transport can send super reactions at all. The
  /// account also needs Nitro, which the caller checks.
  bool get canSendSuperReactions => _repository is SuperReactionRepository;

  /// Adds the account's super reaction to [reaction], or takes it back.
  ///
  /// False when Discord refused it, as it does once the account has none
  /// left; [error] then says why. Nothing changes on screen before Discord
  /// confirms, so there is nothing to roll back.
  Future<bool> toggleSuperReaction(
    ChatMessage message,
    MessageReaction reaction,
  ) => _superReacting(
    (repository) => reaction.burstByCurrentUser
        ? repository.removeSuperReaction(
            channelId: message.channelId,
            messageId: message.id,
            emoji: reaction.key,
          )
        : repository.addSuperReaction(
            channelId: message.channelId,
            messageId: message.id,
            emoji: reaction.key,
          ),
  );

  /// Adds the account's super reaction of [emoji], as [toggleSuperReaction].
  Future<bool> addSuperReaction(ChatMessage message, String emoji) =>
      _superReacting(
        (repository) => repository.addSuperReaction(
          channelId: message.channelId,
          messageId: message.id,
          emoji: emoji,
        ),
      );

  Future<bool> _superReacting(
    Future<void> Function(SuperReactionRepository repository) send,
  ) async {
    if (_repository case final SuperReactionRepository repository) {
      try {
        await send(repository);
        return true;
      } on Object catch (error) {
        AppLog.warning(
          'chat.reaction',
          'A super reaction failed',
          error: error,
        );
        _error = error;
        _notify();
      }
    }
    return false;
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
