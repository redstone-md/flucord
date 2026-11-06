import 'chat_models.dart';

/// One page of the people who voted for a poll answer.
final class PollVotersPage {
  const PollVotersPage({required this.users, required this.hasMore});

  final List<Member> users;
  final bool hasMore;
}

abstract interface class PollRepository {
  Future<ChatMessage> createPoll({
    required String channelId,
    required String authorId,
    required PendingPoll poll,
  });

  Future<ChatMessage> endPoll({
    required String channelId,
    required String messageId,
  });

  /// Who voted for [answerId], oldest first. [afterUserId] is the last voter
  /// of the page before.
  Future<PollVotersPage> loadPollVoters({
    required String channelId,
    required String messageId,
    required int answerId,
    String? afterUserId,
    int limit = 100,
  });
}

/// Voting in a poll. Only a user account can vote: Discord gives a bot no
/// route for it, so the bot transport does not offer this.
abstract interface class PollVoteRepository {
  /// Makes [answerIds] the account's whole vote. An empty set takes the vote
  /// back. Returns the message with the vote counted.
  Future<ChatMessage> votePoll({
    required String channelId,
    required String messageId,
    required Set<int> answerIds,
  });
}
