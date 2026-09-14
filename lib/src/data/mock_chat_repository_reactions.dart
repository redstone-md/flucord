part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryReactions implements ReactionRepository {
  ChatWorkspace get _workspace;
  Future<void> _wait();

  @override
  Future<ReactionUsersPage> loadReactionUsers({
    required String channelId,
    required String messageId,
    required String emoji,
    required DiscordReactionType type,
    String? afterUserId,
    int limit = 100,
  }) async {
    await _wait();
    ChatMessage? message;
    for (final candidate in _workspace.messages) {
      if (candidate.id == messageId) message = candidate;
    }
    MessageReaction? reaction;
    for (final candidate in message?.reactions ?? const <MessageReaction>[]) {
      if (candidate.key == emoji) reaction = candidate;
    }
    final count = type == DiscordReactionType.normal
        ? reaction?.normalCount ?? 0
        : reaction?.burstCount ?? 0;
    final source = type == DiscordReactionType.normal
        ? _workspace.members
        : _workspace.members.reversed;
    final users = source.take(count).toList(growable: false);
    final cursor = afterUserId == null
        ? -1
        : users.indexWhere((member) => member.id == afterUserId);
    final start = (cursor + 1).clamp(0, users.length);
    final end = (start + limit.clamp(1, 100)).clamp(0, users.length);
    return ReactionUsersPage(
      users: users.sublist(start, end),
      hasMore: end < users.length,
    );
  }
}
