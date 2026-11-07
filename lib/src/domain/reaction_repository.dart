import 'member_page.dart';

export 'member_page.dart';

enum DiscordReactionType {
  normal(0),
  burst(1);

  const DiscordReactionType(this.discordValue);

  final int discordValue;
}

abstract interface class ReactionRepository {
  Future<MemberPage> loadReactionUsers({
    required String channelId,
    required String messageId,
    required String emoji,
    required DiscordReactionType type,
    String? afterUserId,
    int limit = 100,
  });
}

/// Super reactions, which Discord sends with the burst reaction type.
///
/// Only a user account offers this. A bot cannot send a super reaction, and
/// Discord gives them only to an account with Nitro.
abstract interface class SuperReactionRepository {
  Future<void> addSuperReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  });

  Future<void> removeSuperReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  });
}
