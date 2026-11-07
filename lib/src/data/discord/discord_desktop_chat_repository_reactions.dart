part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryReactions
    implements ReactionRepository, SuperReactionRepository {
  DiscordDesktopApiClient get _api;
  DiscordMapper get _mapper;

  @override
  Future<MemberPage> loadReactionUsers({
    required String channelId,
    required String messageId,
    required String emoji,
    required DiscordReactionType type,
    String? afterUserId,
    int limit = 100,
  }) async {
    final pageLimit = limit.clamp(1, 100);
    final payloads = await _api.getReactions(
      channelId: channelId,
      messageId: messageId,
      emoji: emoji,
      type: type,
      afterUserId: afterUserId,
      limit: pageLimit,
    );
    return _mapper.reactionUsers(payloads, limit: pageLimit);
  }

  @override
  Future<void> addSuperReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.addReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
    type: DiscordReactionType.burst,
  );

  @override
  Future<void> removeSuperReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.removeReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
    type: DiscordReactionType.burst,
  );

  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.addReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.removeReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );
}
