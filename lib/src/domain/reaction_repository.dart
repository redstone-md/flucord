import 'chat_models.dart';

enum DiscordReactionType {
  normal(0),
  burst(1);

  const DiscordReactionType(this.discordValue);

  final int discordValue;
}

final class ReactionUsersPage {
  const ReactionUsersPage({required this.users, required this.hasMore});

  final List<Member> users;
  final bool hasMore;
}

abstract interface class ReactionRepository {
  Future<ReactionUsersPage> loadReactionUsers({
    required String channelId,
    required String messageId,
    required String emoji,
    required DiscordReactionType type,
    String? afterUserId,
    int limit = 100,
  });
}
