part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryReactions implements ReactionRepository {
  DiscordApiClient get _api;
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
}
